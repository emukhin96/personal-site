# Глава 7. `<head>`, поисковики, соцсети, RSS

## Зачем

Посетитель видит `<body>`. Но страницу «читают» и другие:

- **браузер** — кодировку, масштаб на телефоне, заголовок вкладки, иконку;
- **поисковик** — заголовок и описание для выдачи, основной адрес страницы, список всех страниц сайта;
- **мессенджер или соцсеть** — заголовок, описание и картинку для превью ссылки;
- **RSS-ридер** — список новых записей.

Всё это задаётся в `<head>` и в нескольких служебных файлах (`robots.txt`, `sitemap.xml`, `index.xml`).
В этой главе — `layouts/_partials/head.html` целиком (кроме подключения KaTeX — оно в главе 5), служебные файлы и подвал.

## Как сделано здесь

`layouts/_partials/head.html`:

```go-html-template
{{- $s := hugo.Data.site }}
{{- /* Рендерим контент заранее, чтобы render-хуки успели отметить формулы (hasMath) */}}
{{- $_ := .Content }}
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
{{- $title := cond .IsHome $s.name (printf "%s — %s" .Title $s.name) }}
<title>{{ $title }}</title>
{{- $desc := or .Params.summary $s.description }}
<meta name="description" content="{{ $desc | plainify }}">
<link rel="canonical" href="{{ .Permalink }}">
<meta property="og:title" content="{{ cond .IsHome $s.name .Title }}">
<meta property="og:description" content="{{ $desc | plainify }}">
<meta property="og:type" content="{{ cond .IsPage "article" "website" }}">
<meta property="og:url" content="{{ .Permalink }}">
{{- with partial "resolve-image.html" (dict "page" . "path" .Params.cover) }}
<meta property="og:image" content="{{ (.Fill "1200x630 webp").Permalink }}">
{{- end }}
{{- with site.GetPage "/posts" }}{{ with .OutputFormats.Get "rss" }}
<link rel="alternate" type="application/rss+xml" href="{{ .Permalink }}" title="{{ $s.name }} — записи">
{{- end }}{{ end }}
{{- with $s.avatar }}{{ with partial "resolve-image.html" (dict "path" .) }}
<link rel="icon" href="{{ (.Fill "64x64 png").RelPermalink }}">
{{- end }}{{ end }}
{{- $css := slice (resources.Get "css/syntax.css") (resources.Get "css/main.css") | resources.Concat "css/site.css" | minify | fingerprint }}
<link rel="stylesheet" href="{{ $css.RelPermalink }}" integrity="{{ $css.Data.Integrity }}">
{{- with $s.accent }}
<style>:root{--accent:{{ . | safeCSS }}}</style>
{{- end }}
{{- if .Store.Get "hasMath" }}
<link rel="stylesheet" href="{{ "katex/katex.min.css" | relURL }}">
{{- end }}
```

Его вызывает `layouts/baseof.html` (глава 4):

```go-html-template
<!doctype html>
<html lang="{{ site.Language.Locale }}">
<head>
  {{- partial "head.html" . }}
</head>
```

**Проверено:** для записи «Как начинался проект» получается (переносы строк добавлены для чтения):

```html
<head><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">
<title>Как начинался проект — Ваше имя</title>
<meta name=description content="Первая запись о проекте — с чего всё началось.">
<link rel=canonical href=http://localhost:1313/posts/kak-nachinalsya-proekt/>
<meta property="og:title" content="Как начинался проект">
<meta property="og:description" content="Первая запись о проекте — с чего всё началось.">
<meta property="og:type" content="article">
<meta property="og:url" content="http://localhost:1313/posts/kak-nachinalsya-proekt/">
<link rel=alternate type=application/rss+xml href=http://localhost:1313/posts/index.xml title="Ваше имя — записи">
<link rel=stylesheet href=/css/site.min.a2d2…37cf.css integrity="sha256-otJ5…QN88=">
<style>:root{--accent:#2563eb}</style>
<link rel=stylesheet href=/katex/katex.min.css></head>
```

## Разбор

### Данные сайта: `$s := hugo.Data.site`

`hugo.Data` — содержимое папки `data/`; `hugo.Data.site` — файл `data/site.yaml` (глава 3). Имя, описание, аватар и цвет
берутся оттуда, а не из `hugo.yaml`, потому что этот файл правится в админке («Настройки сайта», глава 8).

**А если иначе.** Раньше писали `site.Data.site` или `.Site.Data.site`. **Проверено:** в Hugo 0.169 это работает, но при сборке
появляется `WARN deprecated: .Site.Data was deprecated in Hugo v0.156.0 and will be removed in a future release. Use hugo.Data instead.`

### `lang`, `charset`, `viewport`

- **`<html lang="ru-RU">`** — язык страницы из `locale: ru-RU` в `hugo.yaml`. **Проверено:** выводится `<html lang="ru-RU">`.
  По нему экранный диктор выбирает произношение, браузер — правила переноса слов (`hyphens: auto`) и предложение перевести страницу.
- **`<meta charset="utf-8">`** — кодировка. Должна быть в первых 1024 байтах документа, поэтому стоит первой. Без неё браузер
  может угадать кодировку неправильно, и кириллица превратится в «кракозябры».
- **`<meta name="viewport" content="width=device-width, initial-scale=1">`** — без этой строки мобильный браузер считает,
  что страница свёрстана для экрана шириной 980px, и показывает её уменьшенной: текст мелкий, медиазапросы из главы 6
  не срабатывают. `width=device-width` — ширина страницы равна ширине экрана, `initial-scale=1` — без начального масштаба.
  Не добавляйте `maximum-scale=1` или `user-scalable=no`: это запрещает людям увеличивать текст.

### `<title>`: заголовок вкладки и выдачи

```go-html-template
{{- $title := cond .IsHome $s.name (printf "%s — %s" .Title $s.name) }}
```

`cond условие а б` — «если условие, то а, иначе б» в одну строку (глава 4). На главной заголовок — просто имя,
на остальных — «Страница — Имя».

**Проверено:**

| Страница | `<title>` |
|---|---|
| Главная | `Ваше имя` |
| Раздел «Проекты» | `Проекты — Ваше имя` |
| Запись | `Как начинался проект — Ваше имя` |
| 404 | `404 Page not found — Ваше имя` |

Последняя строка — недоработка: для страницы 404 Hugo сам задаёт английский заголовок. Исправление:

```go-html-template
{{- $t := cond (eq .Kind "404") "Страница не найдена" .Title }}
{{- $title := cond .IsHome $s.name (printf "%s — %s" $t $s.name) }}
```

**Проверено:** после этого заголовок вкладки — `Страница не найдена — Ваше имя`.

**А если иначе.** Порядок «Страница — Сайт» лучше, чем «Сайт — Страница»: во вкладках и в выдаче заголовок обрезается справа,
и видно самое важное. Поисковики показывают примерно 50–60 символов.

### `description`: текст под заголовком в выдаче

```go-html-template
{{- $desc := or .Params.summary $s.description }}
<meta name="description" content="{{ $desc | plainify }}">
```

- `or а б` возвращает первое непустое значение. У записи и проекта есть поле «Кратко» (`summary`); на главной и в разделах
  его нет, и берётся общее описание сайта из `data/site.yaml`.
- **`plainify`** убирает из строки HTML-теги. Атрибут — это обычный текст, тег внутри него показался бы как есть.

  **Проверено:** `plainify` удаляет только HTML, а разметку Markdown не трогает. Для `summary: Что **изменилось** за "два" месяца &`
  выходит `content="Что **изменилось** за &#34;два&#34; месяца &amp;"`. Звёздочки остались; кавычки и `&` шаблонизатор
  экранировал сам — внутри атрибута это обязательно. Поэтому в поле «Кратко» Markdown писать не стоит. Если нужно разрешить —
  `{{ $desc | markdownify | plainify }}`: сначала превратить в HTML, потом убрать теги.

**А если иначе.** Без `description` поисковик возьмёт кусок текста со страницы сам — часто неудачный (начало меню или подписи).

### `canonical`: основной адрес

```html
<link rel="canonical" href="{{ .Permalink }}">
```

Одна страница может открываться по разным адресам: с `www` и без, с `?utm_source=…`, с `/index.html` на конце.
`canonical` говорит поисковику, какой адрес считать главным, чтобы он не делил «вес» страницы между копиями.

`.Permalink` — полный адрес с доменом из `baseURL`. Локально `baseURL: http://localhost:1313/` — **проверено**:
`canonical` указывает на `http://localhost:1313/posts/kak-nachinalsya-proekt/`. На проде CI передаёт
`hugo --baseURL "$SITE_URL/"` (глава 9). Если переменную `SITE_URL` не задать, на сайте все `canonical`, `og:url` и
ссылки в RSS будут вести на `localhost` — поэтому workflow выводит в этом случае предупреждение.

`.RelPermalink` — адрес без домена (`/posts/…/`). Для ссылок внутри сайта он удобнее, а для `canonical`, Open Graph и RSS
нужен полный адрес: их читают вне сайта.

### Open Graph: превью ссылки

[Open Graph](https://ogp.me) — набор `<meta property="og:…">`, придуманный Facebook и принятый почти всеми: Telegram,
VK, Slack, Discord, LinkedIn, X/Twitter, Mastodon. Когда вы отправляете ссылку, сервис скачивает страницу и строит карточку
из этих полей.

| Поле | Здесь | Зачем |
|---|---|---|
| `og:title` | заголовок страницы без имени сайта (`cond .IsHome $s.name .Title`) | крупный текст карточки |
| `og:description` | то же, что `description` | текст под заголовком |
| `og:type` | `article` для записей и проектов, `website` для остальных | тип объекта. `.IsPage` — истина для обычной страницы, ложь для главной и разделов |
| `og:url` | `.Permalink` | основной адрес — как `canonical` для соцсетей |
| `og:image` | обложка `cover`, обрезанная до 1200×630 | картинка карточки |

**Проверено:** у главной и раздела «Проекты» `og:type` — `website`, у записи — `article`.

#### `og:image`

```go-html-template
{{- with partial "resolve-image.html" (dict "page" . "path" .Params.cover) }}
<meta property="og:image" content="{{ (.Fill "1200x630 webp").Permalink }}">
{{- end }}
```

- `resolve-image.html` находит обложку как ресурс (глава 5). Обложки нет — тега нет.
- **1200×630** — рекомендованный размер (соотношение 1.91:1): в таком виде картинку не обрезают ни Facebook, ни Telegram,
  ни LinkedIn. `.Fill` уменьшает и обрезает до ровно этого размера.
  **Проверено:** обложка 2400×1200 превращается в `cover_hu_….webp` 1200×630.
- **`.Permalink`, а не `.RelPermalink`** — соцсеть скачивает картинку со своего сервера, ей нужен полный адрес.

**А если иначе:**

- **WebP** понимают не все сервисы превью. Telegram, Slack, Discord, Facebook — понимают; некоторые старые парсеры — нет.
  Надёжнее `.Fill "1200x630 jpg q85"`: файл больше, но покажется везде.
- **Картинка по умолчанию.** Сейчас у главной, разделов и записей без обложки картинки в превью нет. Можно взять аватар:

  ```go-html-template
  {{- $img := partial "resolve-image.html" (dict "page" . "path" .Params.cover) }}
  {{- if not $img }}{{ $img = partial "resolve-image.html" (dict "path" $s.avatar) }}{{ end }}
  {{- with $img }}<meta property="og:image" content="{{ (.Fill "1200x630 jpg").Permalink }}">{{ end }}
  ```

  **Проверено:** с аватаром у главной и записи без обложки `og:image` — `…/uploads/me_hu_….jpg`, у проекта — его обложка;
  без аватара и обложки тега нет.
- **Сгенерированная картинка** с заголовком записи — через `images.Text` поверх фона (глава 5).

#### Модификация: `twitter:card`

X/Twitter читает Open Graph, но размер карточки задаётся отдельным тегом:

```html
<meta name="twitter:card" content="summary_large_image">
```

`summary_large_image` — большая картинка над текстом, `summary` (по умолчанию) — маленький квадрат сбоку.
Добавляйте только вместе с `og:image`, внутри того же `with`.

#### Где ещё пригодится

- `article:published_time` — `{{ .Date.Format "2006-01-02T15:04:05Z07:00" }}` для записей.
- `og:locale` — `ru_RU`.
- Проверить, как выглядит карточка: отправьте ссылку себе в Telegram (он кеширует превью — для повторной проверки
  есть бот `@WebpageBot`) или откройте [opengraph.xyz](https://www.opengraph.xyz).

### RSS

RSS — XML-файл со списком последних записей. Ридеры (Feedly, NetNewsWire, Inoreader, Telegram-боты) периодически
скачивают его и показывают новое. Для блога это способ подписаться без соцсетей и почты.

#### Откуда берётся файл

В `hugo.yaml`:

```yaml
outputs:
  home: [html]
  section: [html, rss]
```

**Форматы вывода** (output formats) — какие файлы Hugo делает для страницы каждого вида. У главной — только HTML,
у разделов — HTML и RSS. Поэтому есть `/posts/index.xml` и **нет** `/index.xml`.

У раздела проектов RSS отключён в `content/projects/_index.md`:

```yaml
---
title: Проекты
outputs: [html]
---
```

**Проверено:** в `public/` есть `posts/index.xml`, а `projects/index.xml` и `index.xml` нет.

**А если иначе:**

- `home: [html, rss]` — появится `/index.xml` со всеми страницами сайта, включая проекты. Для блога, где всё — записи,
  так и делают; здесь лента нужна только по записям.
- `section: [html]` — RSS исчезнет. **Проверено:** `posts/index.xml` не создаётся, а ссылки на RSS пропадают из `<head>`
  и подвала: шаблоны обёрнуты в `with`, и пустой результат `OutputFormats.Get "rss"` просто ничего не выводит.

#### Сколько записей в ленте

```yaml
services:
  rss:
    limit: 30
```

**Проверено:** с `limit: 1` в ленте один `<item>`. Без ограничения (по умолчанию `-1`) в ленте все записи — файл растёт
с каждой публикацией, а ридеры скачивают его целиком каждые полчаса.

#### Ссылка на ленту

```go-html-template
{{- with site.GetPage "/posts" }}{{ with .OutputFormats.Get "rss" }}
<link rel="alternate" type="application/rss+xml" href="{{ .Permalink }}" title="{{ $s.name }} — записи">
{{- end }}{{ end }}
```

- `site.GetPage "/posts"` — страница раздела записей, откуда бы ни вызывался шаблон.
- `.OutputFormats.Get "rss"` — её RSS-вариант; у него есть `.Permalink`. Адрес не написан вручную: если поменять формат или
  адрес раздела, ссылка поменяется сама.
- `<link rel="alternate" type="application/rss+xml">` — по нему браузерные расширения и ридеры находят ленту,
  когда вы вставляете в них адрес сайта, а не ленты. Тег стоит на всех страницах, а не только в разделе записей.

#### Свой шаблон ленты

Сейчас используется встроенный шаблон Hugo. **Проверено:** в нём есть английские фразы —
`<title>Записи on Персональный сайт</title>` и `<description>Recent content in Записи on Персональный сайт</description>`.
Заголовок канала берётся из `title` в `hugo.yaml`, а не из `data/site.yaml`.

Свой шаблон заменяет встроенный. **Проверено:** Hugo 0.169 подхватывает для ленты записей любой из файлов
`layouts/posts/section.rss.xml`, `layouts/posts/rss.xml`, `layouts/section.rss.xml`, `layouts/rss.xml`, `layouts/list.rss.xml` —
от самого конкретного к самому общему. Для этого сайта логично `layouts/posts/section.rss.xml`. Набросок:

```go-html-template
{{- $s := hugo.Data.site -}}
{{- printf "<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"yes\"?>" | safeHTML }}
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
  <channel>
    <title>{{ $s.name }} — записи</title>
    <link>{{ .Permalink }}</link>
    <description>{{ $s.description }}</description>
    <language>{{ site.Language.Locale }}</language>
    {{- with .OutputFormats.Get "rss" }}
    <atom:link href="{{ .Permalink }}" rel="self" type="application/rss+xml"/>
    {{- end }}
    {{- range first site.Config.Services.RSS.Limit .Pages.ByDate.Reverse }}
    <item>
      <title>{{ .Title }}</title>
      <link>{{ .Permalink }}</link>
      <guid>{{ .Permalink }}</guid>
      <pubDate>{{ .Date.Format "Mon, 02 Jan 2006 15:04:05 -0700" | safeHTML }}</pubDate>
      <description>{{ .Content | transform.XMLEscape | safeHTML }}</description>
    </item>
    {{- end }}
  </channel>
</rss>
```

Что здесь важно:

- `<link>` канала — адрес HTML-страницы раздела (`.Permalink`), а `atom:link rel="self"` — адрес самой ленты,
  его даёт `.OutputFormats.Get "rss"`. Если перепутать, валидатор ругается, а некоторые ридеры не находят ленту.
- `| safeHTML` у даты: иначе шаблонизатор запишет `+0000` как `&#43;0000`. XML это допускает, но читается хуже.
- `transform.XMLEscape | safeHTML` — HTML текста экранируется для XML один раз (`<p>` → `&lt;p&gt;`), и шаблонизатор не
  экранирует его второй раз.

**Проверено:** Hugo собирает этот шаблон без предупреждений, в ленте 2 записи, заголовок канала — `Ваше имя — записи`,
файл разбирается XML-парсером без ошибок.

Здесь в `<description>` — полный текст записи, а не только «Кратко»: так читать удобнее прямо в ридере. Формулы
в нём будут видны как MathML (глава 5), картинки — по адресам `.RelPermalink`, которые ридер может не разрешить.
Для картинок в ленте используйте `.Permalink` или атрибут `xml:base`. Перед публикацией проверьте ленту валидатором
[validator.w3.org/feed](https://validator.w3.org/feed/).

### Иконка сайта

```go-html-template
{{- with $s.avatar }}{{ with partial "resolve-image.html" (dict "path" .) }}
<link rel="icon" href="{{ (.Fill "64x64 png").RelPermalink }}">
{{- end }}{{ end }}
```

Если в настройках сайта есть фото, оно же становится иконкой вкладки: обрезается в квадрат 64×64.
**Проверено:** с `avatar: /uploads/me.jpg` появляется `<link rel="icon" href="/uploads/me_hu_ff039f08621ac44.png">` —
PNG 64×64; на главной аватар — WebP 176×176.

- **PNG, а не WebP** — иконки показывает не только страница, но и закладки, история, ярлыки. PNG понимают везде.
- **64×64** — вкладке нужно 16–32 пикселя, на экранах 2× — до 64.
- Без аватара тега нет, и браузер запрашивает `/favicon.ico` — получит 404. В логах сервера это видно, на работу сайта не влияет.

**Где ещё пригодится.** Положите `static/favicon.ico` или SVG-иконку `static/icon.svg` и добавьте
`<link rel="icon" href="/icon.svg" type="image/svg+xml">`. Для иконки на домашнем экране iPhone —
`<link rel="apple-touch-icon" href="…">` с картинкой 180×180 (`.Fill "180x180 png"`).

### `robots.txt`

```yaml
enableRobotsTXT: true
```

**Проверено:** Hugo кладёт в корень `robots.txt` с одной строкой `User-agent: *` — «всем роботам можно всё».
С `enableRobotsTXT: false` файла нет (поисковики трактуют это так же, но будут получать 404 на запрос этого файла).

Свой шаблон — `layouts/robots.txt`. **Проверено:**

```
User-agent: *
Disallow: /admin/
Sitemap: {{ "sitemap.xml" | absURL }}
```

даёт файл с полным адресом карты сайта: `Sitemap: http://localhost:1313/sitemap.xml`.

`robots.txt` — просьба, а не запрет: добросовестные роботы её выполняют, остальные игнорируют. Скрыть страницу из выдачи надёжнее
`noindex` (ниже).

### `sitemap.xml`

Карту сайта Hugo делает сам, отдельной настройки для этого нет. **Проверено:** в ней все страницы, у записей и разделов —
`<lastmod>` по дате. У проектов `<lastmod>` нет: у них нет поля `date`, только `started`. Черновики (`draft: true`) в карту и
в RSS не попадают — **проверено**: запись с `draft: true` не встречается ни в `sitemap.xml`, ни в `posts/index.xml`.

**Где ещё пригодится.** Чтобы `lastmod` отражал реальную дату правки, включите `enableGitInfo: true` в `hugo.yaml`:
Hugo возьмёт дату последнего коммита файла. В CI для этого нужна полная история (`fetch-depth: 0` в `actions/checkout`, глава 9).
Отдельную страницу из карты убирает front matter `sitemap: { disable: true }` — **проверено**: запись с ним
пропадает из `sitemap.xml`.

### `noindex` в админке

`static/admin/index.html`:

```html
<meta name="robots" content="noindex">
```

Страница админки публичная (глава 8), но в поиске ей делать нечего. `noindex` просит поисковики не показывать её в выдаче.
Caddy для `/admin/*` дублирует это заголовком `X-Robots-Tag noindex` (глава 10): заголовок действует и на файлы, где `<meta>`
не поставишь, — например `config.yml`.

**А если иначе.** Если запретить `/admin/` в `robots.txt` **вместо** `noindex`, поисковик не сможет скачать страницу и увидеть `noindex`.
Если на неё где-то есть ссылка, адрес может попасть в выдачу без описания. Поэтому основное — `noindex`, а `Disallow` — дополнение.

### Страница 404

`layouts/404.html`:

```go-html-template
{{ define "main" }}
<h1>Страница не найдена</h1>
<p class="muted">Возможно, её переместили или удалили. <a href="{{ "/" | relURL }}">На главную →</a></p>
{{ end }}
```

Hugo собирает её в `public/404.html` в общем каркасе `baseof.html` — с шапкой и подвалом. Сама по себе она ничего не делает:
веб-сервер должен отдавать её на несуществующие адреса с кодом 404. В Caddy за это отвечает блок

```
	handle_errors 404 {
		rewrite * /404.html
		file_server
	}
```

(подробно — в главе 10). Ссылки в ней — через `relURL`, от корня сайта: страница отдаётся по любому неправильному адресу,
относительная ссылка `../` вела бы непонятно куда.

### `rel="me"` в ссылках на главной

`layouts/home.html`:

```go-html-template
  {{- range . }}<li><a href="{{ .url }}"{{ if strings.HasPrefix .url "http" }} rel="me"{{ end }}>{{ .label }}</a></li>{{ end }}
```

`rel="me"` говорит: «по этой ссылке — тоже я». Mastodon использует это для подтверждения ссылок в профиле: если в профиле указан
ваш сайт, а на сайте есть ссылка на профиль с `rel="me"`, ссылка в профиле получит зелёную галочку. Так же поступают
другие сервисы IndieWeb.

`strings.HasPrefix .url "http"` — ставить только к веб-адресам. **Проверено:** ссылка на GitHub выводится с `rel="me"`;
`mailto:` его не получит — для почты он не имеет смысла.

## Подвал

`layouts/_partials/footer.html`:

```go-html-template
{{- $s := hugo.Data.site }}
<footer class="site-footer wrap">
  {{- with $s.footer }}
  <div>{{ . | markdownify }}</div>
  {{- else }}
  <p>© {{ now.Year }} {{ $s.name }}</p>
  {{- end }}
  {{- with site.GetPage "/posts" }}{{ with .OutputFormats.Get "rss" }}
  <p><a href="{{ .RelPermalink }}">RSS</a></p>
  {{- end }}{{ end }}
</footer>
```

- **`with … else`** — если поле «Подвал» заполнено, выводится оно, иначе — «© год имя».
- **`markdownify`** — Markdown в HTML. В поле подвала можно поставить ссылку. **Проверено:** однострочный текст
  `Сделано на [Hugo](https://gohugo.io)` даёт `<div>Сделано на <a href="https://gohugo.io">Hugo</a></div>` — без `<p>`;
  текст из двух абзацев — `<div><p>Абзац 1</p><p>Абзац 2</p></div>`. Для одного абзаца `markdownify` убирает обёртку `<p>`,
  чтобы результат можно было вставить в строку.
- **`now.Year`** — год **на момент сборки**. Сайт пересобирается при каждой правке, но если год сменился, а правок не было,
  в подвале останется прошлый год до следующей сборки. Решение — запускать сборку по расписанию (`on: schedule` в workflow, глава 9).
- **Ссылка на RSS** — та же конструкция, что в `<head>`, но с `.RelPermalink`: ссылка для человека внутри сайта.

## Где ещё пригодится

Структурированные данные [schema.org](https://schema.org) в формате JSON-LD помогают поисковикам показывать расширенные
карточки (автор, дата):

```go-html-template
{{- if eq .Section "posts" }}
<script type="application/ld+json">
{{ dict "@context" "https://schema.org" "@type" "BlogPosting" "headline" .Title "datePublished" (.Date.Format "2006-01-02") "author" (dict "@type" "Person" "name" $s.name) | jsonify | safeJS }}
</script>
{{- end }}
```

**Проверено:** на странице записи выходит
`<script type="application/ld+json">{"@context":"https://schema.org","@type":"BlogPosting","author":{"@type":"Person","name":"Ваше имя"},"datePublished":"2026-01-20","headline":"Как начинался проект"}</script>`.
`jsonify` превращает словарь в JSON, `safeJS` не даёт шаблонизатору экранировать его как строку.

Это не исполняемый JavaScript, а данные — принцип «без JS у посетителя» не нарушается.

## Упражнения

1. Исправьте заголовок страницы 404 (код — в разделе про `<title>`).
2. Добавьте `twitter:card` и запасной `og:image` из аватара. Отправьте ссылку на запись себе в Telegram и посмотрите на карточку.
3. Сделайте свой `layouts/posts/section.rss.xml` с полным текстом записей и русским заголовком канала. Проверьте валидатором.
4. Сделайте `layouts/robots.txt` со строкой `Sitemap:`.
5. Добавьте JSON-LD для записей и проверьте его в [Rich Results Test](https://search.google.com/test/rich-results).

## Итог

`<head>` собирается из данных страницы и `data/site.yaml`: заголовок «Страница — Имя», описание из «Кратко» или общее,
`canonical` и Open Graph с полными адресами из `baseURL`, картинка превью 1200×630 из обложки, иконка из аватара.
RSS есть только у раздела записей (`outputs`), ссылки на ленту строятся через `OutputFormats.Get` и исчезают сами, если формат
отключить. `robots.txt` и `sitemap.xml` Hugo делает сам, админка закрыта от поиска `noindex`, а страница 404 работает вместе
с правилом `handle_errors` в Caddy.

Следующая глава: [Админка на Sveltia CMS →](08-admin-cms.md)
