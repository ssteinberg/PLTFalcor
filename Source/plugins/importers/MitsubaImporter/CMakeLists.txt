add_plugin(MitsubaImporter)

target_sources(MitsubaImporter PRIVATE
    MitsubaImporter.cpp
    MitsubaImporter.h
    Parser.h
    Resolver.h
    Loader.h
    Tables.h
    xml.cpp
)

target_include_directories(MitsubaImporter PRIVATE ../../../../external/mitsuba)
target_include_directories(MitsubaImporter PRIVATE ../../../../external/pugixml)
target_include_directories(MitsubaImporter PRIVATE ../../../../external/packman/deps/include)

target_link_directories(MitsubaImporter PRIVATE ../../../../external/mitsuba/lib)
target_link_directories(MitsubaImporter PRIVATE ../../../../external/pugixml)
target_link_directories(MitsubaImporter PRIVATE ../../../../external/packman/deps/lib)

target_link_libraries(MitsubaImporter PRIVATE mitsuba mitsuba-core pugixml)
target_link_libraries(MitsubaImporter PRIVATE tbb)

target_source_group(MitsubaImporter "Plugins/Importers")

validate_headers(MitsubaImporter)

# Copy mitsuba dlls
add_custom_command(TARGET MitsubaImporter POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        "${CMAKE_SOURCE_DIR}/external/mitsuba/bin/"
        ${FALCOR_OUTPUT_DIRECTORY})
