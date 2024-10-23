// Licensed to the Apache Software Foundation (ASF) under one
// or more contributor license agreements.  See the NOTICE file
// distributed with this work for additional information
// regarding copyright ownership.  The ASF licenses this file
// to you under the Apache License, Version 2.0 (the
// "License"); you may not use this file except in compliance
// with the License.  You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const use_llvm = b.option(bool, "use-llvm", "Use LLVM backend (default: true)") orelse true;
    const use_clang = b.option(bool, "use-clang", "Use libClang codegen (default: true)") orelse true;

    // Generate the Zig bindings for OpenDAL C bindings
    const opendal_binding = b.addTranslateC(.{
        .optimize = optimize,
        .target = target,
        .link_libc = true,
        .root_source_file = b.path("../c/include/opendal.h"),
        .use_clang = use_clang, // TODO: set 'false' use fno-llvm/fno-clang
    });

    // ZigCoro - (stackful) Coroutine for Zig (library)
    const zigcoro = b.dependency("async", .{}).module("libcoro");

    // This function creates a module and adds it to the package's module set, making
    // it available to other packages which depend on this one.
    const opendal_module = b.addModule("opendal", .{
        .root_source_file = b.path("src/opendal.zig"),
        .target = target,
        .optimize = optimize,
    });
    opendal_module.addImport("opendal_c_header", opendal_binding.addModule("opendal_c_header"));
    opendal_module.addIncludePath(b.path("../c/include"));
    opendal_module.addImport("libcoro", zigcoro);

    // Creates a step for building the dependent C bindings
    const libopendal_c_cmake = b.addSystemCommand(&[_][]const u8{ "cmake", "-S", "../c", "-B", "../c/build" });
    const config_libopendal_c = b.step("libopendal_c_cmake", "Generate OpenDAL C binding CMake files");
    config_libopendal_c.dependOn(&libopendal_c_cmake.step);
    const libopendal_c = b.addSystemCommand(&[_][]const u8{ "make", "-C", "../c/build" });
    const build_libopendal_c = b.step("libopendal_c", "Build OpenDAL C bindings");
    libopendal_c.step.dependOn(config_libopendal_c);
    build_libopendal_c.dependOn(&libopendal_c.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("test/bdd.zig"),
        .target = target,
        .optimize = optimize,
        .use_llvm = use_llvm,
        .test_runner = b.dependency("test_runner", .{}).path("test_runner.zig"),
    });

    if (optimize == .Debug) {
        unit_tests.addLibraryPath(b.path("../c/target/debug"));
    } else {
        unit_tests.addLibraryPath(b.path("../c/target/release"));
    }
    unit_tests.linkSystemLibrary("opendal_c");
    unit_tests.linkLibCpp();
    unit_tests.root_module.addImport("opendal", opendal_module);

    // Creates a step for running unit tests.
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run OpenDAL Zig bindings tests");
    test_step.dependOn(&libopendal_c.step);
    test_step.dependOn(&run_unit_tests.step);
}
