from pathlib import Path
import sys

from conan import ConanFile
from conan.tools.build import check_min_cppstd
from conan.tools.cmake import CMakeDeps, CMakeToolchain, cmake_layout


sys.path.insert(0, str(Path(__file__).resolve().parent / "conan"))
from dependencies_generated import VERSIONS


required_conan_version = ">=2.31.1"


class CppBoostNativeExampleConan(ConanFile):
    settings = "os", "arch", "compiler", "build_type"

    def configure(self):
        self.options["boost"].shared = False
        # Conan's Boost package config declares every component target. Keep
        # the test library present so loading BoostConfig.cmake never refers to
        # a component artifact omitted from the package.
        self.options["boost"].without_test = False
        self.options["grpc"].shared = False
        self.options["grpc"].codegen = True
        self.options["asio-grpc"].backend = "boost"
        self.options["jemalloc"].shared = True

    def requirements(self):
        self.requires(f"boost/{VERSIONS['boost']}", override=True)
        self.requires(f"protobuf/{VERSIONS['protobuf']}", override=True)
        self.requires(
            f"grpc/{VERSIONS['grpc']}@gorundebug/boost", override=True
        )
        self.requires(f"asio-grpc/{VERSIONS['asio-grpc']}")
        self.requires(f"jemalloc/{VERSIONS['jemalloc']}")

    def build_requirements(self):
        self.tool_requires(f"protobuf/{VERSIONS['protobuf']}", override=True)

    def validate(self):
        if self.settings.get_safe("compiler.cppstd"):
            check_min_cppstd(self, "20")

    def layout(self):
        cmake_layout(self)

    def generate(self):
        CMakeDeps(self).generate()
        toolchain = CMakeToolchain(self)
        toolchain.generate()
