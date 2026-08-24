.PHONY: docker-build docker-test docker-asan docker-tsan docker-up docker-down conan-lock clean

docker-build:
	@./scripts/docker-build-target.sh inventoryservice cppboostnativeexample-inventoryservice:latest
	@./scripts/docker-build-target.sh orderservice cppboostnativeexample-orderservice:latest

docker-test:
	@./scripts/docker-build-target.sh test cppboostnativeexample-test:latest

docker-asan:
	@./scripts/docker-build-target.sh asan-test cppboostnativeexample-asan-test:latest

docker-tsan:
	@./scripts/docker-build-target.sh tsan-test cppboostnativeexample-tsan-test:latest

docker-up: docker-build
	@bash -c 'source scripts/dependency-proxy-env.sh && docker compose up -d --no-build'

docker-down:
	@docker compose down --volumes --remove-orphans

conan-lock:
	@./scripts/conan-lock.sh

clean:
	@docker compose down --volumes --remove-orphans
