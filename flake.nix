{
  description = "Logos Qt SDK - the Qt developer layer (LogosAPI, provider base classes, QObject provider glue) over logos-protocol";

  inputs = {
    logos-nix.url = "github:logos-co/logos-nix";
    nixpkgs.follows = "logos-nix/nixpkgs";
    # Keep protocol inputs on the maintained fork so downstream fork builds do
    # not silently switch back to the upstream repository.
    logos-protocol = {
      url = "github:3esmit/logos-protocol?rev=3f307064aea1a7a6747f0374b8216c0549d1aceb";
      inputs.logos-nix.follows = "logos-nix";
    };
    # The canonical, language-neutral LIDL frontend the qt-generator links.
    logos-lidl = {
      url = "github:logos-co/logos-lidl/2043d8bf94c6bfee3781f96ad088e8c13ec36038";
      inputs.logos-nix.follows = "logos-nix";
    };
    # Where the Qt host runtime lives now: logos-plugin-qt's `logos-qt-host`
    # package owns LogosAPI, LogosAPIProvider, LogosProviderBase, the QObject
    # adapter and the Qt argument decoder. This SDK re-exports it.
    #
    # The three `follows` are load-bearing, not tidiness. logos-qt-host links
    # logos-protocol, and so does this SDK; if the two resolved to different
    # logos-protocol revisions the closure would carry two TokenManagers, two
    # transport registries and two of every other function-local static in
    # there — the exact split-brain the Windows single-provider work spent
    # itself closing, reintroduced through the lock file instead of the linker.
    #
    # Pin the provider glue to the upstream commit carrying the inbound token
    # delivery fix. The three `follows` above keep one logos-protocol in the
    # closure; this explicit pin keeps the provider/consumer behavior reproducible.
    logos-plugin-qt = {
      url = "github:logos-co/logos-plugin-qt/3a471be14af66d099827ee712ec8c40ead701340";
      inputs.logos-nix.follows = "logos-nix";
      inputs.logos-protocol.follows = "logos-protocol";
      inputs.logos-lidl.follows = "logos-lidl";
    };
    # Two things, neither of them a generated test fixture any more: the
    # `cpp-generator` package ships the shared LIDL frontend sources that
    # logos-qt-generator compiles (share/lidl-frontend, see nix/qt-generator.nix),
    # and `logos-cpp-include` supplies the Qt-free headers this SDK's host
    # veneer and the test suite's single-TU compile check include.
    #
    # It used to also generate tests/qt-sdk's provider-dispatch fixture via
    # `logos-cpp-generator --provider-header`; that flag, and the
    # `interface: "provider"` authoring path behind it, were removed.
    # Keep the C++ SDK input on the maintained fork as well.
    logos-cpp-sdk = {
      url = "github:3esmit/logos-cpp-sdk?rev=a4b7550470b0ad874bb7c20ed95df8e5a7bdd8c8";
      inputs.logos-nix.follows = "logos-nix";
      inputs.logos-protocol.follows = "logos-protocol";
      inputs.logos-lidl.follows = "logos-lidl";
    };
  };

  outputs = { self, nixpkgs, logos-nix, logos-protocol, logos-lidl, logos-cpp-sdk, logos-plugin-qt }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];

      # logos-nix's crates.io fixes. Without them this flake builds a SECOND,
      # un-overlaid Qt, so a module closure ends up carrying two qtdeclaratives
      # and still fetching crate sources from the endpoint crates.io 403s.
      # Windows takes mkWindowsPkgs, which owns its own overlay list.
      mkPkgs = system: import nixpkgs {
        inherit system;
        overlays = logos-nix.lib.nativeOverlays;
      };

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f {
        inherit system;
        pkgs = mkPkgs system;
        protocolLib = logos-protocol.packages.${system}.logos-protocol-lib;
        cppGenerator = logos-cpp-sdk.packages.${system}.cpp-generator;
        # Headers only — the base SDK's include set, needed by the test suite's
        # single-TU compile check (see nix/tests.nix). Not part of any shipped
        # package here: this SDK's own sources do not include them.
        cppSdkInclude = logos-cpp-sdk.packages.${system}.logos-cpp-include;
        lidlPkg = logos-lidl.packages.${system}.logos-lidl;
        qtHost = logos-plugin-qt.packages.${system}.logos-qt-host;
      });

      # Same as forAllSystems, plus the "x86_64-windows" pseudo-system. This
      # cannot just be logos-nix.lib.forAllTargets, because that only supplies
      # { system, pkgs } and this flake also threads per-system dependencies
      # through.
      #
      # Keying the Windows target as a SYSTEM is what keeps
      # `dep.packages.${system}.foo` working untouched -- the dependency flakes
      # expose the same pseudo-system.
      windowsBuildSystem = "x86_64-linux";
      forAllTargets = f:
        nixpkgs.lib.genAttrs (systems ++ [ "x86_64-windows" ]) (system:
          let
            isWin = system == "x86_64-windows";
            pkgs =
              if isWin then logos-nix.lib.mkWindowsPkgs { buildSystem = windowsBuildSystem; }
              else mkPkgs system;
            protocolLib = logos-protocol.packages.${system}.logos-protocol-lib;
          in
          f {
            inherit system pkgs;

            # Target-side library: follows the target.
            inherit protocolLib;
            lidlPkg = logos-lidl.packages.${system}.logos-lidl;

            # The Qt host runtime, taken from logos-plugin-qt for EVERY target
            # including Windows. That repo keys `packages` by forAllTargets, so
            # packages.x86_64-windows.logos-qt-host is a real mingw build there.
            # This flake used to carry nix/qt-host-windows.nix, a second recipe
            # over the same sources, because plugin-qt published the unix systems
            # only; logos-plugin-qt#19 added the Windows target and that file
            # said to delete it the moment it did.
            qtHost = logos-plugin-qt.packages.${system}.logos-qt-host;

            # HOST TOOL: the code generator is executed during the build, so it
            # must be a native binary for the machine doing the building. Taking
            # it from packages.x86_64-windows would hand the Linux builder a PE
            # it cannot run -- the same rule that puts repc/moc in
            # QT_HOST_PATH rather than the target Qt.
            cppGenerator =
              logos-cpp-sdk.packages.${if isWin then windowsBuildSystem else system}.cpp-generator;

            # Headers, so target-typed like every other include set here — but
            # architecture-independent in practice, since the package installs
            # sources and nothing else. Only the test suite consumes it.
            cppSdkInclude = logos-cpp-sdk.packages.${system}.logos-cpp-include;
          });
    in
    {
      packages = forAllTargets ({ pkgs, protocolLib, cppGenerator, cppSdkInclude, lidlPkg, qtHost, ... }:
        let
          common = import ./nix/default.nix { inherit pkgs; };
          src = ./.;

          lib = import ./nix/lib.nix { inherit pkgs common src protocolLib qtHost cppSdkInclude; };
          qtGenerator = import ./nix/qt-generator.nix {
            inherit pkgs src;
            cppGeneratorBin = cppGenerator;
            logos-lidl = lidlPkg;
          };
          include = import ./nix/include.nix { inherit pkgs common src; };
          tests = import ./nix/tests.nix {
            inherit pkgs common src protocolLib cppGenerator cppSdkInclude qtGenerator qtHost;
          };

          qtSdk = pkgs.symlinkJoin {
            name = "logos-qt-sdk";
            paths = [ lib include ];
            # qtHost is propagated by the JOIN as well as by `lib`, because
            # symlinkJoin does not inherit the propagated inputs of the paths it
            # joins and this attribute — not `lib` — is what consumers add to
            # their buildInputs. Without it a consumer's find_package(
            # logos-qt-sdk) would fall back to the Config's baked HINTS instead
            # of resolving logos-qt-host off CMAKE_PREFIX_PATH.
            propagatedBuildInputs = common.propagatedBuildInputs ++ [ qtHost ];
          };
        in
        {
          logos-qt-sdk-lib = lib;
          logos-qt-sdk-include = include;
          inherit tests;

          logos-qt-sdk = qtSdk;
          logos-qt-generator = qtGenerator;
          default = qtSdk;
        }
      );

      checks = forAllSystems ({ pkgs, protocolLib, cppGenerator, cppSdkInclude, lidlPkg, qtHost, ... }:
        let
          common = import ./nix/default.nix { inherit pkgs; };
          src = ./.;
          qtGenerator = import ./nix/qt-generator.nix {
            inherit pkgs src;
            cppGeneratorBin = cppGenerator;
            logos-lidl = lidlPkg;
          };
          tests = import ./nix/tests.nix {
            inherit pkgs common src protocolLib cppGenerator cppSdkInclude qtGenerator qtHost;
          };
        in
        {
          inherit tests;
        }
      );

      devShells = forAllSystems ({ pkgs, protocolLib, cppGenerator, lidlPkg, qtHost, ... }: {
        default = pkgs.mkShell {
          nativeBuildInputs = [
            pkgs.cmake
            pkgs.ninja
            pkgs.pkg-config
          ];
          buildInputs = [
            pkgs.qt6.qtbase
            pkgs.qt6.qtremoteobjects
            pkgs.gtest
            pkgs.boost
            pkgs.openssl
            pkgs.nlohmann_json
            protocolLib
            qtHost
            cppGenerator
          ];
          shellHook = ''
            export LOGOS_PROTOCOL_ROOT="${protocolLib}"
            export LOGOS_QT_HOST_ROOT="${qtHost}"
          '';
        };
      });
    };
}
