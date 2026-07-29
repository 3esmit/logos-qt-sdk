#include <gtest/gtest.h>
#include "logos_mock.h"
#include "logos_api.h"
#include "logos_api_client.h"
#include "logos_api_provider.h"

class LogosApiTest : public ::testing::Test {
protected:
    void SetUp() override
    {
        m_mock = new LogosMockSetup();
    }
    void TearDown() override
    {
        delete m_mock;
    }
    LogosMockSetup* m_mock = nullptr;
};

TEST_F(LogosApiTest, ConstructionCreatesProvider)
{
    LogosAPI api("test_module");
    EXPECT_NE(api.getProvider(), nullptr);
}

TEST_F(LogosApiTest, GetTokenManagerReturnsSingleton)
{
    LogosAPI api("test_module");
    EXPECT_EQ(api.getTokenManager(), &TokenManager::instance());
}

TEST_F(LogosApiTest, GetClientReturnsNonNull)
{
    LogosAPI api("origin");
    LogosAPIClient* client = api.getClient("target_module");
    EXPECT_NE(client, nullptr);
}

TEST_F(LogosApiTest, GetClientCachesSameModule)
{
    LogosAPI api("origin");
    LogosAPIClient* client1 = api.getClient("target");
    LogosAPIClient* client2 = api.getClient("target");
    EXPECT_EQ(client1, client2);
}

TEST_F(LogosApiTest, GetClientDifferentModulesReturnDifferentClients)
{
    LogosAPI api("origin");
    LogosAPIClient* a = api.getClient("module_a");
    LogosAPIClient* b = api.getClient("module_b");
    EXPECT_NE(a, b);
}

TEST_F(LogosApiTest, LegacyClientCacheKeyUsesDefaultInstance)
{
    const LogosAPIClientCacheKey key{
        QStringLiteral("target"), LogosMode::Mock, LogosTransportConfig{}};

    EXPECT_TRUE(key.targetInstanceId.isEmpty());
}

TEST_F(LogosApiTest, ScopedProviderUsesDistinctRegistry)
{
    LogosAPI lez("lez_indexer_module", QStringLiteral("zone_0101"));
    LogosAPI paradox("lez_indexer_module", QStringLiteral("zone_8888"));

    EXPECT_EQ(lez.getProvider()->registryUrl(),
              QStringLiteral("local:logos_lez_indexer_module_zone_0101"));
    EXPECT_EQ(paradox.getProvider()->registryUrl(),
              QStringLiteral("local:logos_lez_indexer_module_zone_8888"));
    EXPECT_NE(lez.getProvider()->registryUrl(), paradox.getProvider()->registryUrl());
}

TEST_F(LogosApiTest, ScopedTargetClientsDoNotAlias)
{
    LogosAPI api("origin");

    LogosAPIClient* lez = api.getClient(
        QStringLiteral("lez_indexer_module"), QStringLiteral("zone_0101"));
    LogosAPIClient* paradox = api.getClient(
        QStringLiteral("lez_indexer_module"), QStringLiteral("zone_8888"));
    LogosAPIClient* legacy = api.getClient(QStringLiteral("lez_indexer_module"));

    ASSERT_NE(lez, nullptr);
    ASSERT_NE(paradox, nullptr);
    ASSERT_NE(legacy, nullptr);
    EXPECT_NE(lez, paradox);
    EXPECT_NE(lez, legacy);
    EXPECT_NE(paradox, legacy);
    EXPECT_EQ(lez->registryUrl(),
              QStringLiteral("local:logos_lez_indexer_module_zone_0101"));
    EXPECT_EQ(paradox->registryUrl(),
              QStringLiteral("local:logos_lez_indexer_module_zone_8888"));
    EXPECT_EQ(legacy, api.getClient(
        QStringLiteral("lez_indexer_module"), QString{}));
}

TEST_F(LogosApiTest, MultipleLogosApiInstances)
{
    LogosAPI api1("mod1");
    LogosAPI api2("mod2");
    EXPECT_NE(api1.getProvider(), api2.getProvider());
    // Both share the same token manager singleton
    EXPECT_EQ(api1.getTokenManager(), api2.getTokenManager());
}
