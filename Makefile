MOUNT := $(PWD)
DOCKER_RUN = docker run -v $(MOUNT):/app -w /app -e GOPATH=/app

BIN = $(GOPATH)/bin
NODE_BIN = $(shell npm bin)
PID = .pid
GO_FILES = $(filter-out src/app/server/bindata.go, $(shell find src/app -type f -name "*.go"))
TEMPLATES = $(wildcard src/app/server/data/templates/*.html)
BINDATA = src/app/server/bindata.go
BINDATA_FLAGS = -pkg=server -prefix=src/app/server/data
BUNDLE = src/app/server/data/static/build/bundle.js
APP = $(shell find src/app/client -type f)

build: clean $(BIN)/app

clean:
	@rm -rf src/app/server/data/static/build/*
	@rm -rf src/app/server/data/bundle.server.js
	@rm -rf $(BINDATA)
	@echo cleaned

$(BUNDLE): $(APP)
	$(DOCKER_RUN) --rm node ./node_modules/.bin/webpack --progress --colors

$(BIN)/app: $(BUNDLE) $(BINDATA)
	$(DOCKER_RUN) --rm golang go install -ldflags "-w -X main.buildstamp=`date -u '+%Y-%m-%d_%I:%M:%S%p'` -X main.gittag=`git describe --tags || true` -X main.githash=`git rev-parse HEAD || true`" app

kill:
	-docker kill `cat $(PID)` || true
	-docker rm `cat $(PID)` || true
	-docker kill `cat .cidhot` || true
	-docker kill `cat .cidwebpack` || true
	rm -rf $(PID) .cidhot .cidwebpack

serve: clean $(BUNDLE)
	@make restart
	$(DOCKER_RUN) --rm -i --cidfile=.cidhot -e BABEL_ENV=dev --link `cat $(PID)`:app -p 5001:5001 node node hot.proxy &
	$(DOCKER_RUN) --rm -i --cidfile=.cidwebpack node ./node_modules/.bin/webpack --watch &
	fswatch $(GO_FILES) $(TEMPLATES) | xargs -n1 -I{} make restart || make kill

restart: BINDATA_FLAGS += -debug
restart: $(BINDATA)
	@echo restart the app...
	@$(DOCKER_RUN) --rm golang go install app
	docker restart `cat $(PID)` || rm -rf $(PID) && $(DOCKER_RUN) -itd --cidfile=$(PID) --expose 5000 golang bin/app run

$(BINDATA):
	$(DOCKER_RUN) --rm -it golang bin/go-bindata $(BINDATA_FLAGS) -o=$@ src/app/server/data/...

lint:
	@$(DOCKER_RUN) --rm node node_modules/.bin/eslint src/app/client || true
	@$(DOCKER_RUN) --rm golang bin/golint $(filter-out src/app/main.go, $(GO_FILES)) || true
	@$(DOCKER_RUN) --rm golang bin/golint -min_confidence=1 app
