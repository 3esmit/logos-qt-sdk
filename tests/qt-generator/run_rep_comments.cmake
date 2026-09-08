file(MAKE_DIRECTORY "${OUT_DIR}")
file(WRITE "${OUT_DIR}/metadata.json" "{\"name\":\"probe\",\"version\":\"1.0.0\"}")
string(ASCII 239 187 191 UTF8_BOM)
set(CASES
    "class Actual\n{\n}\n"
    "// class Legacy\nclass Actual\n{\n}\n"
    "/*\nclass Legacy\n*/\nclass Actual\n{\n}\n"
    "/** class Legacy ***/\n\tclass Actual\r\n{\n}\n"
    "// /* class Legacy\nclass Actual\n{\n}\n"
    "// /* class Legacy\nclass Actual\n{\n}\n/* later comment */\n"
    "/* // class Legacy\nclass Hidden\n*/\nclass Actual\n{\n}\n"
    "/* class Legacy */ class Actual\n{\n}\n"
    "#include \"class Legacy\"\n  class Actual\n{\n}\n"
    "class Actual\n{\n}\nclass Second\n{\n}\n"
    "${UTF8_BOM}class Actual\n{\n}\n"
    "${UTF8_BOM}/* class Legacy */ class Actual\n{\n}\n"
)
set(INDEX 0)
foreach(CONTENTS IN LISTS CASES)
    math(EXPR INDEX "${INDEX} + 1")
    set(DEST "${OUT_DIR}/case-${INDEX}")
    file(WRITE "${OUT_DIR}/probe.rep" "${CONTENTS}")
    execute_process(COMMAND "${GENERATOR}" --backend ui
        --metadata "${OUT_DIR}/metadata.json" --rep "${OUT_DIR}/probe.rep"
        --output-dir "${DEST}" RESULT_VARIABLE RESULT OUTPUT_VARIABLE STDOUT ERROR_VARIABLE STDERR)
    if(NOT RESULT EQUAL 0)
        message(FATAL_ERROR "Case ${INDEX} failed: ${STDOUT}${STDERR}")
    endif()
    file(READ "${DEST}/probe_ui_glue.h" HEADER)
    if(NOT HEADER MATCHES "public ActualViewPluginBase" OR HEADER MATCHES "Legacy|Hidden|SecondViewPluginBase")
        message(FATAL_ERROR "Case ${INDEX}: generated glue selected a commented or later class")
    endif()
    if(INDEX EQUAL 1)
        set(BASELINE "${DEST}")
    else()
        foreach(NAME probe_ui_interface.h probe_ui_glue.h probe_ui_glue.cpp)
            execute_process(COMMAND "${CMAKE_COMMAND}" -E compare_files "${BASELINE}/${NAME}" "${DEST}/${NAME}"
                RESULT_VARIABLE DIFFERENT)
            if(NOT DIFFERENT EQUAL 0)
                message(FATAL_ERROR "Case ${INDEX}: ${NAME} differs from the comment-free output")
            endif()
        endforeach()
    endif()
endforeach()

file(WRITE "${OUT_DIR}/probe.rep" "// class Legacy\n/*\nclass Hidden\n*/\n")
execute_process(COMMAND "${GENERATOR}" --backend ui
    --metadata "${OUT_DIR}/metadata.json" --rep "${OUT_DIR}/probe.rep"
    --output-dir "${OUT_DIR}/missing" RESULT_VARIABLE RESULT ERROR_VARIABLE STDERR)
if(RESULT EQUAL 0 OR NOT STDERR MATCHES "no `class <Name>` declaration found")
    message(FATAL_ERROR "Comments-only input was not rejected for its missing class: ${STDERR}")
endif()
message(STATUS "REP_CLASS_COMMENTS_OK: ${INDEX} byte-identical cases and missing-class rejection")
