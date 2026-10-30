# Заметки для агентов

- Сайт на Hugo без внешней темы: шаблоны в `layouts/` (структура Hugo ≥ 0.146: `home.html`, `<section>/page.html`, `_partials/`, `_markup/`).
- Контент правит владелец через Sveltia CMS (`static/admin/config.yml`). Любое изменение полей во front matter или в `data/site.yaml` делать **одновременно** в шаблонах и в конфиге админки; конфиг проверять по схеме `@sveltia/cms/schema/sveltia-cms.json`.
- Связь «запись → проекты»: поле `projects` записи = список имён папок в `content/projects/`. Логика — `_partials/project-posts.html` и `_partials/post-projects.html`.
- Картинки: путь без `/` — ресурс рядом с записью, `/uploads/...` — `assets/uploads/`. Разрешение пути — `_partials/resolve-image.html`.
- Темы — `assets/css/themes/<имя>.css`: токены `--l-*`/`--d-*`, шрифты, размеры поверх `main.css`; выбор — `theme` в `data/site.yaml`, режим — `mode` (атрибут `data-mode` на `<html>`). Цвета в правилах брать только из токенов, чтобы работали оба режима.
- Внешних JS/CSS на сайте нет (KaTeX — `static/katex/`, шрифты тем — `static/fonts/`); админка грузит Sveltia с unpkg.
- Проверка перед PR: `hugo --gc --minify` без WARN/ERROR.
- Тексты интерфейса — на русском.
