cmake_minimum_required(VERSION 3.21)
project(savvycan_innomaker LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

set(CMAKE_OSX_ARCHITECTURES_INPUT "${CMAKE_OSX_ARCHITECTURES}")
unset(CMAKE_OSX_ARCHITECTURES CACHE)

find_package(QT NAMES Qt6 Qt5 REQUIRED COMPONENTS Core SerialBus)
find_package(Qt${QT_VERSION_MAJOR} REQUIRED COMPONENTS Core SerialBus)

set(SAVVYCAN_APP "" CACHE PATH "Optional path to SavvyCAN.app. When set, validate architecture and link Qt frameworks from the app bundle.")
set(SAVVYCAN_APP_INPUT "${SAVVYCAN_APP}")
unset(SAVVYCAN_APP CACHE)

set(INNOMAKER_USBIO_LIB "${CMAKE_CURRENT_SOURCE_DIR}/libInnoMakerUSBIOLib.dylib" CACHE FILEPATH "Path to INNO-MAKER libInnoMakerUSBIOLib.dylib")

if(NOT EXISTS "${INNOMAKER_USBIO_LIB}")
    message(FATAL_ERROR "INNOMAKER_USBIO_LIB does not exist: ${INNOMAKER_USBIO_LIB}")
endif()

add_library(InnoMakerUsbIOLib SHARED IMPORTED GLOBAL)
set_target_properties(InnoMakerUsbIOLib PROPERTIES
    IMPORTED_LOCATION "${INNOMAKER_USBIO_LIB}"
)

add_library(innomakerusb2can MODULE
    innomakercanbackend.h
    innomakercanbackend.mm
    innomakercanplugin.mm
)

if(SAVVYCAN_APP_INPUT)
    set(SAVVYCAN_EXECUTABLE "${SAVVYCAN_APP_INPUT}/Contents/MacOS/SavvyCAN")
    set(SAVVYCAN_FRAMEWORKS_DIR "${SAVVYCAN_APP_INPUT}/Contents/Frameworks")

    if(NOT EXISTS "${SAVVYCAN_EXECUTABLE}")
        message(FATAL_ERROR "SavvyCAN executable not found: ${SAVVYCAN_EXECUTABLE}")
    endif()

    execute_process(
        COMMAND lipo -archs "${SAVVYCAN_EXECUTABLE}"
        OUTPUT_VARIABLE SAVVYCAN_ARCHS_OUTPUT
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE SAVVYCAN_ARCHS_RESULT
        ERROR_QUIET
    )

    if(SAVVYCAN_ARCHS_RESULT EQUAL 0)
        separate_arguments(SAVVYCAN_ARCHS_LIST UNIX_COMMAND "${SAVVYCAN_ARCHS_OUTPUT}")

        if(CMAKE_OSX_ARCHITECTURES_INPUT)
            string(REPLACE ";" " " CMAKE_OSX_ARCHITECTURES_LIST "${CMAKE_OSX_ARCHITECTURES_INPUT}")
            foreach(SAVVYCAN_REQUIRED_ARCH IN LISTS CMAKE_OSX_ARCHITECTURES_INPUT)
                if(NOT SAVVYCAN_ARCHS_OUTPUT MATCHES "(^| )${SAVVYCAN_REQUIRED_ARCH}($| )")
                    message(FATAL_ERROR
                        "SavvyCAN.app architecture '${SAVVYCAN_ARCHS_OUTPUT}' does not match "
                        "CMAKE_OSX_ARCHITECTURES='${CMAKE_OSX_ARCHITECTURES_LIST}'.")
                endif()
            endforeach()
        else()
            set(SAVVYCAN_TARGET_ARCHS "${SAVVYCAN_ARCHS_LIST}")
        endif()
    endif()

    execute_process(
        COMMAND otool -L "${SAVVYCAN_EXECUTABLE}"
        OUTPUT_VARIABLE SAVVYCAN_OTOOL_OUTPUT
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )

    if(SAVVYCAN_OTOOL_OUTPUT MATCHES "QtCore\\.framework/Versions/A/QtCore")
        set(SAVVYCAN_QT_VERSION_MAJOR 6)
    elseif(SAVVYCAN_OTOOL_OUTPUT MATCHES "QtCore\\.framework/Versions/5/QtCore")
        set(SAVVYCAN_QT_VERSION_MAJOR 5)
    else()
        message(FATAL_ERROR "Unable to detect Qt major version from ${SAVVYCAN_EXECUTABLE}")
    endif()

    if(NOT SAVVYCAN_QT_VERSION_MAJOR EQUAL QT_VERSION_MAJOR)
        message(FATAL_ERROR
            "SavvyCAN.app uses Qt${SAVVYCAN_QT_VERSION_MAJOR}, but the current toolchain resolved Qt${QT_VERSION_MAJOR}. "
            "Update CMAKE_PREFIX_PATH to a matching Qt installation.")
    endif()

    if(SAVVYCAN_OTOOL_OUTPUT MATCHES "@executable_path/\.\./Frameworks/QtCore\.framework/"
       AND SAVVYCAN_OTOOL_OUTPUT MATCHES "@executable_path/\.\./Frameworks/QtSerialBus\.framework/")
        set(SAVVYCAN_USES_BUNDLED_QT TRUE)
    else()
        set(SAVVYCAN_USES_BUNDLED_QT FALSE)
    endif()

    if(SAVVYCAN_USES_BUNDLED_QT)
        set(SAVVYCAN_QT_CORE_LIB "${SAVVYCAN_FRAMEWORKS_DIR}/QtCore.framework/QtCore")
        set(SAVVYCAN_QT_SERIALBUS_LIB "${SAVVYCAN_FRAMEWORKS_DIR}/QtSerialBus.framework/QtSerialBus")

        if(NOT EXISTS "${SAVVYCAN_QT_CORE_LIB}")
            message(FATAL_ERROR "SavvyCAN QtCore framework not found: ${SAVVYCAN_QT_CORE_LIB}")
        endif()

        if(NOT EXISTS "${SAVVYCAN_QT_SERIALBUS_LIB}")
            message(FATAL_ERROR "SavvyCAN QtSerialBus framework not found: ${SAVVYCAN_QT_SERIALBUS_LIB}")
        endif()

        execute_process(
            COMMAND otool -D "${SAVVYCAN_QT_CORE_LIB}"
            OUTPUT_VARIABLE SAVVYCAN_QT_CORE_ID_OUTPUT
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        string(REPLACE "\n" ";" SAVVYCAN_QT_CORE_ID_LIST "${SAVVYCAN_QT_CORE_ID_OUTPUT}")
        list(LENGTH SAVVYCAN_QT_CORE_ID_LIST SAVVYCAN_QT_CORE_ID_LIST_LENGTH)
        if(SAVVYCAN_QT_CORE_ID_LIST_LENGTH GREATER 1)
            list(GET SAVVYCAN_QT_CORE_ID_LIST 1 SAVVYCAN_QT_CORE_INSTALL_NAME)
        else()
            set(SAVVYCAN_QT_CORE_INSTALL_NAME "${SAVVYCAN_QT_CORE_LIB}")
        endif()

        execute_process(
            COMMAND otool -D "${SAVVYCAN_QT_SERIALBUS_LIB}"
            OUTPUT_VARIABLE SAVVYCAN_QT_SERIALBUS_ID_OUTPUT
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        string(REPLACE "\n" ";" SAVVYCAN_QT_SERIALBUS_ID_LIST "${SAVVYCAN_QT_SERIALBUS_ID_OUTPUT}")
        list(LENGTH SAVVYCAN_QT_SERIALBUS_ID_LIST SAVVYCAN_QT_SERIALBUS_ID_LIST_LENGTH)
        if(SAVVYCAN_QT_SERIALBUS_ID_LIST_LENGTH GREATER 1)
            list(GET SAVVYCAN_QT_SERIALBUS_ID_LIST 1 SAVVYCAN_QT_SERIALBUS_INSTALL_NAME)
        else()
            set(SAVVYCAN_QT_SERIALBUS_INSTALL_NAME "${SAVVYCAN_QT_SERIALBUS_LIB}")
        endif()
    endif()
endif()

if(SAVVYCAN_TARGET_ARCHS)
    set_target_properties(innomakerusb2can PROPERTIES
        OSX_ARCHITECTURES "${SAVVYCAN_TARGET_ARCHS}"
    )
elseif(CMAKE_OSX_ARCHITECTURES_INPUT)
    set_target_properties(innomakerusb2can PROPERTIES
        OSX_ARCHITECTURES "${CMAKE_OSX_ARCHITECTURES_INPUT}"
    )
endif()

target_include_directories(innomakerusb2can PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    $<TARGET_PROPERTY:Qt${QT_VERSION_MAJOR}::Core,INTERFACE_INCLUDE_DIRECTORIES>
    $<TARGET_PROPERTY:Qt${QT_VERSION_MAJOR}::SerialBus,INTERFACE_INCLUDE_DIRECTORIES>
)

target_compile_definitions(innomakerusb2can PRIVATE
    $<TARGET_PROPERTY:Qt${QT_VERSION_MAJOR}::Core,INTERFACE_COMPILE_DEFINITIONS>
    $<TARGET_PROPERTY:Qt${QT_VERSION_MAJOR}::SerialBus,INTERFACE_COMPILE_DEFINITIONS>
)

if(SAVVYCAN_APP_INPUT AND SAVVYCAN_USES_BUNDLED_QT)
    target_link_libraries(innomakerusb2can PRIVATE
        "${SAVVYCAN_QT_CORE_LIB}"
        "${SAVVYCAN_QT_SERIALBUS_LIB}"
        InnoMakerUsbIOLib
        "-framework Foundation"
        "-framework IOKit"
    )
else()
    target_link_libraries(innomakerusb2can PRIVATE
        Qt${QT_VERSION_MAJOR}::Core
        Qt${QT_VERSION_MAJOR}::SerialBus
        InnoMakerUsbIOLib
        "-framework Foundation"
        "-framework IOKit"
    )
endif()

set_target_properties(innomakerusb2can PROPERTIES
    AUTOMOC ON
    BUNDLE FALSE
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/canbus"
    BUILD_RPATH "@loader_path"
    INSTALL_RPATH "@loader_path"
    PREFIX "lib"
    SUFFIX ".dylib"
)

add_custom_command(TARGET innomakerusb2can POST_BUILD
    COMMAND install_name_tool -change
        "@executable_path/../Frameworks/libInnoMakerUSBIOLib.dylib"
        "@loader_path/libInnoMakerUSBIOLib.dylib"
        "$<TARGET_FILE:innomakerusb2can>"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${INNOMAKER_USBIO_LIB}"
        "$<TARGET_FILE_DIR:innomakerusb2can>/"
)

if(SAVVYCAN_APP_INPUT AND SAVVYCAN_USES_BUNDLED_QT)
    add_custom_command(TARGET innomakerusb2can POST_BUILD
        COMMAND install_name_tool -change
            "${SAVVYCAN_QT_CORE_INSTALL_NAME}"
            "@executable_path/../Frameworks/QtCore.framework/QtCore"
            "$<TARGET_FILE:innomakerusb2can>"
        COMMAND install_name_tool -change
            "${SAVVYCAN_QT_SERIALBUS_INSTALL_NAME}"
            "@executable_path/../Frameworks/QtSerialBus.framework/QtSerialBus"
            "$<TARGET_FILE:innomakerusb2can>"
    )
endif()


install(TARGETS innomakerusb2can
    LIBRARY DESTINATION canbus
)
