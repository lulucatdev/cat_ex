.PHONY: help deps format format-check test docs hex-build preflight publish release

help:
	@printf "Available targets:\n"
	@printf "  deps                - Fetch dependencies\n"
	@printf "  format              - Format source code\n"
	@printf "  format-check        - Check formatting without changing files\n"
	@printf "  test                - Run test suite\n"
	@printf "  docs                - Build HexDocs locally\n"
	@printf "  hex-build           - Build Hex package tarball\n"
	@printf "  preflight           - Run all release checks\n"
	@printf "  publish             - Publish to Hex.pm\n"
	@printf "  release             - preflight + publish\n"

deps:
	mix deps.get

format:
	mix format

format-check:
	mix format --check-formatted

test:
	mix test

docs:
	mix docs

hex-build:
	mix hex.build

preflight: deps format-check test docs hex-build

publish:
	mix hex.publish

release: preflight publish
