HUGO ?= hugo

.PHONY: dev build clean

dev: ## Локальный сервер с черновиками: http://localhost:1313
	$(HUGO) server --buildDrafts --disableFastRender

build: ## Сборка в public/ как на проде
	$(HUGO) --gc --minify

clean:
	rm -rf public resources/_gen .hugo_build.lock
