.PHONY: docker-build docker-test docker-asan docker-tsan docker-up docker-down conan-lock clean

docker-build:
	@./scripts/docker-build-target.sh inventoryservice cppboostnativeexample-inventoryservice:local
	@./scripts/docker-build-target.sh orderservice cppboostnativeexample-orderservice:local

docker-test:
	@./scripts/docker-build-target.sh test cppboostnativeexample-test:local

docker-asan:
	@./scripts/docker-build-target.sh asan-test cppboostnativeexample-asan-test:local

docker-tsan:
	@./scripts/docker-build-target.sh tsan-test cppboostnativeexample-tsan-test:local

docker-up: docker-build
	@bash -c 'source scripts/dependency-proxy-env.sh && docker compose up -d --no-build'

docker-down:
	@docker compose down --volumes --remove-orphans

conan-lock:
	@./scripts/conan-lock.sh

clean:
	@docker compose down --volumes --remove-orphans
