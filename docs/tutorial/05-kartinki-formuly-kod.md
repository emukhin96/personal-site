# Глава 5. Картинки, формулы, код

## Зачем

В Markdown картинка пишется как `![описание](файл.png)`, формула — как `\(x^2\)`, код — как блок в тройных обратных кавычках.
Сам Markdown не знает, что с ними делать дальше. Без доработки получилось бы так:

- картинка с телефона на 4000 пикселей и 5 МБ уходит посетителю как есть;
- формула остаётся текстом `\(x^2\)` или требует подключить JavaScript-библиотеку в браузере;
- код выводится одним цветом.

В этом проекте всё это делается **при сборке**: картинки уменьшаются и переводятся в WebP, формулы превращаются
в готовый HTML, код раскрашивается. У посетителя нет ни одного скрипта (принцип 2 из главы 1).

Инструмент для этого — **render-хуки** (render hooks): шаблоны, которые Hugo вызывает вместо своего стандартного
вывода для отдельных элементов Markdown.

## Render-хуки: общая идея

Hugo превращает Markdown в HTML парсером [Goldmark](https://github.com/yuin/goldmark). Для некоторых элементов
он сначала смотрит, есть ли в `layouts/_markup/` шаблон с нужным именем. Если есть — HTML этого элемента
пишет ваш шаблон, если нет — Goldmark сам.

| Файл в `layouts/_markup/` | Когда вызывается | Что приходит в шаблон (главное) |
|---|---|---|
| `render-image.html` | `![alt](src "title")` | `.Destination`, `.PlainText`, `.Title`, `.IsBlock`, `.Page` |
| `render-link.html` | `[текст](url "title")` | `.Destination`, `.Text`, `.Title` |
| `render-heading.html` | `## Заголовок` | `.Level`, `.Anchor`, `.Text` |
| `render-codeblock.html` | блок кода в ` ``` ` | `.Type` (язык), `.Inner`, `.Attributes`, `.Options` |
| `render-codeblock-mermaid.html` | блок ` ```mermaid ` (имя после дефиса — язык) | то же |
| `render-passthrough.html` | текст между разделителями passthrough (здесь — формулы) | `.Inner`, `.Type` (`inline`/`block`) |
| `render-blockquote.html` | `> цитата`, в том числе `> [!NOTE]` | `.Text`, `.Type` (`regular`/`alert`), `.AlertType` |
| `render-table.html` | таблица Markdown | `.THead`, `.TBody`, `.Attributes` |

В проекте два хука: `render-image.html` и `render-passthrough.html`. Код подсвечивается встроенным механизмом,
без хука.

Хук можно сделать только для одного раздела: `layouts/posts/_markup/render-image.html` сработает
только в записях, а для остальных страниц останется общий `layouts/_markup/render-image.html`.
**Проверено** на тестовом разделе: хук из `layouts/<раздел>/_markup/` применился только к его страницам.

Важно: хуки работают **только для Markdown**. Картинка, вставленная в шаблон тегом `<img>`, через хук не проходит.
Поэтому логика обработки картинок вынесена в partial'ы, которые зовут и хук, и шаблоны.

## Картинки

### Как сделано здесь

Три файла, каждый со своей задачей:

```
resolve-image.html  путь из Markdown или front matter → ресурс Hugo (или «нет такого»)
img.html            ресурс → <img> нужного размера в WebP
render-image.html   хук: ![…](…) → resolve-image → img → при необходимости <figure>
```

Кто их вызывает:

| Откуда | Что | Через что |
|---|---|---|
| Текст записи `![…](chart.png "…")` | картинка в тексте | `render-image.html` → `resolve-image.html` → `img.html` |
| `layouts/posts/page.html`, `layouts/projects/page.html` | обложка `cover` | `resolve-image.html` → `img.html` |
| `layouts/home.html` | аватар `avatar` из `data/site.yaml` | `resolve-image.html` → `.Fill` |
| `layouts/_partials/head.html` | `og:image` и иконка | `resolve-image.html` → `.Fill` (глава 7) |

### `resolve-image.html`: найти картинку

`layouts/_partials/resolve-image.html`:

```go-html-template
{{- /*
  Находит картинку как ресурс Hugo, чтобы её можно было уменьшить и сжать.
  path — значение из front matter или Markdown:
    "cover.jpg"         → файл рядом с записью (page bundle);
    "/uploads/x.jpg"    → общая медиатека, assets/uploads/x.jpg.
  Возвращает ресурс или nil (внешняя ссылка, файл не найден).
*/}}
{{- $res := false }}
{{- with .path }}
  {{- $path := . }}
  {{- if not (strings.Contains $path "://") }}
    {{- with $.page }}{{ $res = .Resources.Get $path }}{{ end }}
    {{- if not $res }}{{ $res = resources.Get (strings.TrimPrefix "/" $path) }}{{ end }}
  {{- end }}
{{- end }}
{{- return $res }}
```

#### Разбор

Чтобы Hugo мог изменить картинку, она должна быть **ресурсом** — файлом, который Hugo прочитал и знает его размеры.
Ресурсы бывают двух видов:

- **ресурсы страницы** — файлы в папке бандла рядом с `index.md` (глава 3). Достаются через `.Resources.Get "cover.jpg"`
  у конкретной страницы;
- **глобальные ресурсы** — файлы в папке `assets/`. Достаются через `resources.Get "uploads/me.jpg"`
  (путь от `assets/`, без ведущего `/`).

Файлы из `static/` ресурсами **не являются**: Hugo копирует их как есть и не умеет их обрабатывать.
Поэтому общая медиатека админки лежит в `assets/uploads/`, а не в `static/uploads/` (глава 8).

Порядок поиска:

1. `strings.Contains $path "://"` — внешняя ссылка (`https://…`). Её не скачиваем, `$res` остаётся `false`.
2. `with $.page` — если передали страницу, ищем файл среди её ресурсов. `$` здесь — словарь, который передали в partial
   (глава 4), а `$.page` — его поле `page`. Аватар вызывается без страницы, `(dict "path" .)`, поэтому этот шаг пропускается.
3. Если не нашли — `resources.Get` в `assets/`. `strings.TrimPrefix "/"` превращает адрес из админки
   `/uploads/me.jpg` в путь `uploads/me.jpg` относительно `assets/`.
4. `return $res` — partial возвращает значение, а не HTML (глава 4). Вызывающий пишет
   `with partial "resolve-image.html" …` и внутри `with` получает ресурс.

#### А если иначе

- **Файла нет.** Partial возвращает `false`, и хук выводит обычный `<img src="missing.png">` — битую картинку.
  **Проверено:** `![нет](missing.png "Нет файла")` даёт `<figure><img src="missing.png" …><figcaption>Нет файла</figcaption></figure>`,
  предупреждения при сборке нет. Если хотите узнавать об опечатках при сборке, добавьте в `render-image.html`
  в ветку `else` строку `{{ if not (strings.Contains .Destination "://") }}{{ warnf "Нет картинки %s в %s" .Destination .Page.File.Path }}{{ end }}`,
  а в CI запускайте `hugo --panicOnWarning`, чтобы сборка падала.
- **Только `.Resources.Get`, без `resources.Get`.** Картинки из общей медиатеки перестанут обрабатываться и
  пойдут битыми ссылками `/uploads/…`: в `static/` их нет, а сами по себе файлы из `assets/` на сайт не попадают.
  **Проверено:** файл `assets/uploads/me.jpg` в `public/` не копируется — туда попадают только его обработанные версии
  (`me_hu_….webp`). Файл из `assets/` публикуется, только когда шаблон обратится к его `.RelPermalink` или `.Permalink`.
- **Внешние картинки тоже обрабатывать.** Есть `resources.GetRemote "https://…"`: Hugo скачает файл при сборке,
  и с ним можно делать то же, что с локальным. Минус — сборка зависит от чужого сервера. Здесь так не делают.

### `img.html`: уменьшить и сжать

`layouts/_partials/img.html`:

```go-html-template
{{- /* Выводит <img> из ресурса: растровые картинки уменьшаются до width и переводятся в WebP. */}}
{{- $res := .res }}
{{- $width := .width | default 1440 }}
{{- if in (slice "jpg" "jpeg" "png" "webp" "tiff" "bmp") (strings.TrimPrefix "image/" $res.MediaType.SubType) }}
  {{- if gt $res.Width $width }}
    {{- $res = $res.Resize (printf "%dx webp" $width) }}
  {{- else }}
    {{- $res = $res.Process "webp" }}
  {{- end }}
<img src="{{ $res.RelPermalink }}" width="{{ $res.Width }}" height="{{ $res.Height }}" alt="{{ .alt }}"{{ with .class }} class="{{ . }}"{{ end }}{{ if not .eager }} loading="lazy"{{ end }} decoding="async">
{{- else }}
<img src="{{ $res.RelPermalink }}" alt="{{ .alt }}"{{ with .class }} class="{{ . }}"{{ end }}{{ if not .eager }} loading="lazy"{{ end }} decoding="async">
{{- end }}
```

Partial принимает словарь: `res` — ресурс, `alt` — описание, необязательные `width` (по умолчанию 1440),
`class` и `eager`.

#### Какие картинки обрабатываются

`$res.MediaType.SubType` — вторая часть MIME-типа: для `image/jpeg` это `jpeg`, для `image/svg+xml` — `svg+xml`.
`strings.TrimPrefix "image/"` здесь подстраховка: `SubType` уже без префикса.
`in (slice …) значение` проверяет, есть ли значение в списке.

Обрабатываются только растровые форматы, которые Hugo умеет перекодировать. Остальные выводятся как есть:

- **SVG** — векторная картинка, её не нужно уменьшать: она чёткая при любом размере. У ресурса SVG нет `.Width` и `.Height`,
  а `.Resize` для него — ошибка сборки. **Проверено:** `error calling Resize: resource "logo.svg" of media type "image/svg+xml" does not support this method`.
- **GIF** — обычно это анимация. Перекодирование анимации — отдельная история (размер, число кадров, поддержка в формате),
  поэтому GIF в список не включён и отдаётся как есть.

**Проверено:** `![svg](logo.svg "Подпись SVG")` даёт `<img src="/t/logo.svg" alt="svg" loading="lazy" decoding="async">`
без `width`/`height` — сработала вторая ветка.

#### Методы обработки

У ресурса-картинки есть пять методов. Все принимают строку-«спецификацию»: размеры, формат, качество, фильтр, якорь.

| Метод | Что делает | Пример |
|---|---|---|
| `.Resize "600x"` | Ширина 600, высота по пропорции. `"x300"` — наоборот. `"600x300"` — ровно так, пропорции искажаются | обычные иллюстрации |
| `.Fit "600x600"` | Вписывает в рамку, сохраняя пропорции. **Не увеличивает** | превью «не больше чем» |
| `.Fill "600x600"` | Заполняет рамку целиком: уменьшает и обрезает лишнее | аватар, `og:image` |
| `.Crop "600x600"` | Только обрезает до размера, без уменьшения | вырезать фрагмент |
| `.Process "webp"` | Любая операция строкой; без размеров — только сменить формат | `"resize 600x webp q70"` |

**Проверено** на картинке 2400×1200:

| Вызов | Результат |
|---|---|
| `.Resize "600x"` | 600×300 |
| `.Resize "x300"` | 600×300 |
| `.Fit "600x600"` | 600×300 |
| `.Fill "600x600"` | 600×600 |
| `.Crop "600x600"` | 600×600 |
| `.Fit "3000x3000"` | 2400×1200 — не увеличила |
| `.Resize "3000x"` | 3000×1500 — **увеличила** |
| `.Process "webp"` | 2400×1200, формат webp |

Последние две строки объясняют проверку `gt $res.Width $width`: `Resize` увеличивает маленькие картинки,
а увеличенная картинка тяжелее и не становится чётче. Поэтому широкие картинки уменьшаются до 1440 пикселей,
а узкие только переводятся в WebP через `.Process`.

**А если иначе.** Вместо `if` можно было написать `$res.Fit (printf "%dx%d webp" $width 10000)`: `Fit` сам не увеличивает.
Получилось бы короче, но смысл кода был бы менее очевиден.

Почему 1440: колонка текста — 40rem = 640 CSS-пикселей (глава 6), на экране с плотностью 2× это 1280 физических пикселей.
1440 даёт запас. Если вёрстка станет шире, увеличьте значение по умолчанию.

#### Что ещё можно указать в спецификации

- **Формат**: `webp`, `jpg`, `png`, `gif`, `tif`, `bmp`, а в Hugo 0.169 ещё и `avif`.
  **Проверено:** та же фотография шириной 1440 весит 6946 байт в WebP и 4801 байт в AVIF.
- **Качество** `q1`…`q100` для jpg/webp/avif. Если не указано — берётся из `imaging` в `hugo.yaml`.
  **Проверено** на фотографии шириной 1440: `q50` — 4174 байта, `q82` — 6946, `q100` — 49552; JPEG `q82` — 23436, PNG — 159393.
- **Подсказка для WebP**: `photo` (по умолчанию), `picture`, `drawing`, `icon`, `text`. И `lossless` — сжатие без потерь.
  **Проверено** на демо-графике `chart.png` (6572 байта): обычный WebP — 8410 байт, то есть **больше исходника**;
  `webp drawing` — 5654; `webp lossless` — 1132. Для схем и скриншотов с ровными цветами WebP с потерями — не лучший выбор.
- **Фильтр уменьшения**: `lanczos`, `catmullrom`, `mitchellnetravali`, `linear`, `box`, `nearestneighbor` и др.
  Lanczos даёт самую чёткую картинку, `box` быстрее, `nearestneighbor` сохраняет пиксели резкими (для пиксель-арта).
  На размер файла фильтр почти не влияет: **проверено** — 6946 / 7002 / 7006 байт для lanczos / box / nearestneighbor.
- **Якорь** для `Fill` и `Crop`: `Smart` (по умолчанию — Hugo сам ищет «интересную» часть), `Center`, `TopLeft`, `Top`,
  `Bottom` и т. д. Аватар с лицом в верхней части кадра лучше обрезать с `Top`.
- **Поворот** `r90`, **цвет фона** `#ffffff` для прозрачных PNG при переводе в JPEG.

Значения по умолчанию задаются в `hugo.yaml`:

```yaml
imaging:
  webp:
    quality: 82
  resampleFilter: lanczos
```

В Hugo 0.169 оба значения и так стоят по умолчанию (**проверено** командой `hugo config`). В конфиге они записаны явно,
чтобы не зависеть от смены умолчаний в будущих версиях и чтобы было видно, где их менять.

#### Атрибуты `<img>`

- `width` и `height` — **настоящие** размеры обработанной картинки. Браузер ещё до загрузки знает пропорции и резервирует место.
  Без них текст под картинкой «прыгает», когда она догрузится (метрика CLS в Lighthouse).
  CSS `img { max-width: 100%; height: auto; }` (глава 6) уменьшает картинку под колонку, а пропорции берутся из этих атрибутов.
- `loading="lazy"` — грузить, только когда картинка приближается к экрану. `eager` в словаре отключает его:
  обложка видна сразу, откладывать её загрузку не нужно — это замедлило бы первую отрисовку.
- `decoding="async"` — браузер может декодировать картинку, не останавливая отрисовку остальной страницы.
- `alt` — текст для экранных дикторов и на случай, если картинка не загрузилась. Обложки выводятся с `alt=""`:
  это декоративная картинка, и пустой `alt` говорит диктору её пропустить. Без атрибута `alt` диктор прочитал бы имя файла.

#### Где ещё пригодится

- **Адаптивные картинки.** Несколько размеров и `srcset`, чтобы телефон получал маленький файл:

  ```go-html-template
  {{- $small := $res.Resize "720x webp" }}
  {{- $large := $res.Resize "1440x webp" }}
  <img src="{{ $large.RelPermalink }}"
       srcset="{{ $small.RelPermalink }} 720w, {{ $large.RelPermalink }} 1440w"
       sizes="(max-width: 40rem) 100vw, 40rem"
       width="{{ $large.Width }}" height="{{ $large.Height }}" alt="{{ .alt }}">
  ```
- **AVIF с запасным WebP** через `<picture>`: браузер возьмёт первый формат, который понимает.

  ```go-html-template
  <picture>
    <source srcset="{{ ($res.Resize "1440x avif").RelPermalink }}" type="image/avif">
    <img src="{{ ($res.Resize "1440x webp").RelPermalink }}" …>
  </picture>
  ```
- **Фильтры**: `images.Filter` с `images.GaussianBlur`, `images.Grayscale`, `images.Text` (надпись поверх картинки —
  так генерируют `og:image` с заголовком статьи).
- **EXIF**: `.Exif` или `.Meta` — дата съёмки, камера, координаты. При перекодировании Hugo метаданные не переносит,
  поэтому в WebP координат нет. Но **оригинал из папки бандла тоже публикуется**: **проверено** — в `public/projects/primer-proekta/`
  лежит и `cover.jpg`, и его WebP-версии. Если в фотографии с телефона есть GPS, его можно прочитать из оригинала.
  Удаляйте метаданные перед загрузкой или запретите публиковать оригиналы во front matter:

  ```yaml
  build:
    publishResources: false
  ```

  **Проверено:** с этой настройкой в папке страницы остаётся только `photo_hu_….webp`, оригинала `photo.jpg` нет.
  Обработанные версии публикуются, потому что шаблон обратился к их `.RelPermalink`.

### `render-image.html`: картинка из Markdown

`layouts/_markup/render-image.html`:

```go-html-template
{{- $img := "" }}
{{- with partial "resolve-image.html" (dict "page" .Page "path" .Destination) }}
  {{- $img = partial "img.html" (dict "res" . "alt" $.PlainText) }}
{{- else }}
  {{- $img = printf `<img src="%s" alt="%s" loading="lazy" decoding="async">` (.Destination | safeURL) .PlainText }}
{{- end }}
{{- if and .IsBlock .Title }}
<figure>{{ $img | safeHTML }}<figcaption>{{ .Title }}</figcaption></figure>
{{- else }}{{ $img | safeHTML }}{{ end -}}
```

#### Разбор

Для строки `![Рост чего-нибудь](chart.png "Картинки лежат в папке записи рядом с текстом")` хук получает:

| Поле | Значение |
|---|---|
| `.Destination` | `chart.png` — что в круглых скобках |
| `.PlainText` | `Рост чего-нибудь` — текст в квадратных скобках без разметки, идёт в `alt` |
| `.Text` | то же, но с разметкой, если она была (`*курсив*` → `<em>`) |
| `.Title` | `Картинки лежат в папке записи рядом с текстом` — текст в кавычках, идёт в подпись |
| `.IsBlock` | `true`, если картинка — единственное содержимое абзаца |
| `.Page` | страница, в тексте которой стоит картинка: нужна, чтобы найти файл в её бандле |
| `.Attributes` | атрибуты в фигурных скобках после картинки (`{.wide}`), если включены в настройках Goldmark |

Логика:

1. Нашли ресурс — HTML строит `img.html`. Не нашли (внешняя ссылка, опечатка) — простой `<img>` через `printf`.
   `safeURL` говорит шаблонизатору, что адрес безопасен: иначе необычные схемы адресов заменились бы на `#ZgotmplZ`.
2. Если картинка стоит отдельным абзацем **и** у неё есть title — оборачиваем в `<figure>` с `<figcaption>`.
   Иначе выводим просто `<img>`. В HTML title не попадает: у этого атрибута плохая доступность, а подпись под картинкой видят все.

**Проверено:** результат для демо-записи:

```html
<figure><img src=/posts/pervoe-obnovlenie/chart_hu_7d04b0a439e38e96.webp width=1440 height=810 alt="Рост чего-нибудь" loading=lazy decoding=async><figcaption>Картинки лежат в папке записи рядом с текстом</figcaption></figure>
```

PNG 1600×900 превратился в WebP 1440×810, подпись — в `<figcaption>`. Кавычки у атрибутов убрал `--minify`.

#### `wrapStandAloneImageWithinParagraph` и `.IsBlock`

По стандарту Markdown картинка на отдельной строке — это абзац с картинкой внутри: `<p><img></p>`.
`<figure>` внутри `<p>` по правилам HTML поставить нельзя. Поэтому в `hugo.yaml`:

```yaml
markup:
  goldmark:
    parser:
      wrapStandAloneImageWithinParagraph: false
```

С `false` Goldmark не оборачивает такую картинку в `<p>` и ставит `.IsBlock = true` — хук сам решает, что вывести.

**Проверено:** с `true` выходит

```html
<p>
<img src="/posts/pervoe-obnovlenie/chart_hu_7d04b0a439e38e96.webp" width="1440" height="810" alt="Рост чего-нибудь" loading="lazy" decoding="async">
</p>
```

— без `<figure>` и без подписи: `.IsBlock` всегда `false`.

**Проверено:** картинка внутри текста (`Текст и картинка в строке ![inline](small.png "Заголовок") тут.`) выводится как `<img>`
внутри `<p>`, подпись пропадает. Так и задумано: подпись посреди строки не нужна.

#### Зачем `safeHTML`

Шаблоны Hugo экранируют любые строки: `<` превращается в `&lt;`, чтобы чужой текст не мог вставить на страницу HTML или скрипт.
Partial `img.html` возвращает значение типа «безопасный HTML», а вот `printf` — обычную строку.

**Проверено:** если убрать `| safeHTML`, картинка-ресурс выводится нормально, а внешняя картинка (ветка `printf`)
превращается в текст `<figure>&lt;img src=&#34;https://example.com/a.png&#34; alt=&#34;…` прямо на странице.

`safeHTML` здесь безопасен: данные в `printf` — из Markdown владельца сайта, а не от посетителей.
Не применяйте `safeHTML` к данным, которые пришли извне.

#### Где ещё пригодится

- **Классы через атрибуты.** Включите `markup.goldmark.parser.attribute.block: true`, и в Markdown можно написать
  `![…](…)` и на следующей строке `{.wide}`. В хуке это `.Attributes.class` — можно сделать картинки шире колонки.
  **Проверено:** с настройкой хук получает `.Attributes` = `map[class:wide]` и `.IsBlock` = `true`; без неё `{.wide}`
  остаётся текстом на странице, а картинка перестаёт быть отдельным абзацем (`.IsBlock` = `false`).
- **`render-link.html`**: добавлять `rel="noopener"` и значок к внешним ссылкам, проверять, что внутренние ссылки
  ведут на существующие страницы (`site.GetPage`).
- **`render-heading.html`**: значок-якорь `#` рядом с заголовком, чтобы можно было скопировать ссылку на раздел.

## Формулы

### Как сделано здесь

Формулы в тексте записи:

```markdown
Формула внутри строки: \(e^{i\pi} + 1 = 0\), и отдельной строкой:

$$
\sum_{k=1}^{n} k = \frac{n(n+1)}{2}
$$
```

Настройки Goldmark в `hugo.yaml`:

```yaml
    extensions:
      passthrough:
        enable: true
        delimiters:
          block: [['\[', '\]'], ['$$', '$$']]
          inline: [['\(', '\)']]
```

Хук `layouts/_markup/render-passthrough.html`:

```go-html-template
{{- /* Формулы \( … \), \[ … \], $$ … $$ рендерятся в HTML при сборке (KaTeX внутри Hugo), без JS в браузере. */}}
{{- $opts := dict "output" "htmlAndMathml" "displayMode" (eq .Type "block") }}
{{- with try (transform.ToMath .Inner $opts) }}
  {{- with .Err }}
    {{- warnf "Формула не распознана (%s): %s" $.Position . }}
    <code>{{ $.Inner }}</code>
  {{- else }}
    {{- .Value }}
    {{- $.Page.Store.Set "hasMath" true }}
  {{- end }}
{{- end -}}
```

И в `layouts/_partials/head.html`:

```go-html-template
{{- /* Рендерим контент заранее, чтобы render-хуки успели отметить формулы (hasMath) */}}
{{- $_ := .Content }}
…
{{- if .Store.Get "hasMath" }}
<link rel="stylesheet" href="{{ "katex/katex.min.css" | relURL }}">
{{- end }}
```

### Разбор

#### Passthrough: не трогать текст формулы

В формулах много символов, которые для Markdown что-то значат: `_` — курсив, `*` — жирный, `\` — экранирование.
Без защиты `\sum_{k=1}` Markdown испортил бы ещё до того, как формула куда-то попала.

Расширение **passthrough** говорит Goldmark: всё между этими разделителями — не Markdown, отдай как есть.
Результат идёт в хук `render-passthrough.html`, а `.Type` говорит, какие это были разделители:

- `block` — `\[ … \]` или `$$ … $$`: формула отдельной строкой, по центру, крупно;
- `inline` — `\( … \)`: формула внутри текста.

Одиночный `$ … $` для формул в строке **намеренно не включён**: доллар часто встречается в обычном тексте.
**Проверено:** строка `Цена $5 и $10 долларов.` выводится как обычный текст. Если бы в `inline` был `['$', '$']`,
кусок `5 и ` стал бы формулой.

#### `transform.ToMath`: KaTeX внутри Hugo

`transform.ToMath` — функция Hugo, в которую встроен [KaTeX](https://katex.org). Она принимает текст формулы (`.Inner`)
и словарь опций и возвращает готовый HTML. Node.js не нужен.

Опции:

| Опция | Здесь | Что значит | Другие варианты |
|---|---|---|---|
| `output` | `htmlAndMathml` | HTML для отображения + MathML для экранных дикторов и копирования | `html` — только HTML; `mathml` — только MathML |
| `displayMode` | `(eq .Type "block")` | `true` — блочная формула: крупнее, по центру, `\sum` с пределами сверху и снизу | всегда `false` — все формулы как строчные |
| `throwOnError` | не задано (`true`) | ошибка в формуле → функция возвращает ошибку | `false` — нарисует формулу красным с текстом ошибки во всплывающей подсказке |
| `errorColor` | — | цвет ошибочной формулы при `throwOnError: false` | любой CSS-цвет |
| `macros` | — | свои команды: `dict "\\R" "\\mathbb{R}"` | — |
| `minRuleThickness`, `fleqn` | — | толщина дробной черты; блочные формулы слева, а не по центру | — |

**Проверено** — размер страницы демо-записи с двумя формулами:

| `output` | Размер HTML | Что внутри |
|---|---|---|
| `htmlAndMathml` | 7394 байта | `<span class="katex-mathml"><math>…</math></span><span class="katex-html" aria-hidden="true">…` |
| `html` | 6626 байт | только `katex-html` — дикторы ничего не прочтут |
| `mathml` | 3493 байта | только `<math>…</math>` |

Вариант `mathml` самый лёгкий, и все современные браузеры рисуют MathML сами. Но выглядит он хуже, чем вёрстка KaTeX
(другие шрифты и отступы). `htmlAndMathml` — самый надёжный выбор: красиво и доступно.

#### `try`, `.Err`, `warnf`: ошибка в формуле не валит сборку

`try` выполняет функцию и, если она упала, не останавливает шаблон, а возвращает объект с полями `.Err` (ошибка) и `.Value` (результат).

**Проверено:** формула `\(\frac{1}{\)` (не закрыта скобка) даёт при сборке предупреждение

```
WARN  Формула не распознана (".../content/t/index.md:4:15"): … KaTeX parse error: Unexpected end of input in a macro argument, expected '}' at end of input: \frac{1}{
```

а на странице — `<code>\frac{1}{</code>`. Сайт собрался, текст формулы виден.

- `$.Position` — файл, строка и столбец формулы. `$`, а не `.`, потому что внутри `with` точка уже указывает на результат `try` (глава 4).
- `warnf` пишет в лог `WARN`. Есть ещё `errorf` — пишет `ERROR` и завершает сборку с ошибкой; `erroridf` / `warnidf` — то же,
  но предупреждение можно отключить через `ignoreLogs`.

**А если иначе:**

- **Без `try`.** **Проверено:** сборка падает с `ERROR error building site: render: … failed to render pages`.
  Одна опечатка в формуле — и сайт не выкладывается. Иногда так и надо (строгий режим), но владельцу через админку
  такую ошибку сложно найти.
- **`"throwOnError" false`.** **Проверено:** предупреждений нет, на странице красная формула
  `<span class="katex-error" title="ParseError: KaTeX parse error: …" style="color:#cc0000">\frac{1}{</span>`.
  Удобно при наборе, но ошибку легко не заметить.

#### `hasMath`: стили KaTeX только там, где есть формулы

Вёрстке KaTeX нужен файл стилей и шрифты (`static/katex/katex.min.css` и `static/katex/fonts/`, около 300 КБ).
Подключать их на каждую страницу незачем. Поэтому хук после успешной формулы ставит отметку
`$.Page.Store.Set "hasMath" true`, а `head.html` подключает стили, только если отметка есть.

`.Store` — «блокнот» страницы: в него можно класть значения из любого шаблона и читать их из любого другого
в рамках одной сборки. Есть ещё `hugo.Store` — общий для всего сайта.

Тонкость — в порядке. `head.html` выполняется раньше, чем `.Content` в `main`: `<head>` стоит в `baseof.html` выше `<main>`.
Хуки запускаются, когда Hugo впервые рендерит текст страницы. Если ничего не сделать, при выполнении `head.html` отметки ещё нет.
Поэтому первая строка `head.html` — `{{ $_ := .Content }}`: рендерим текст заранее и выбрасываем результат.
Hugo кеширует `.Content`, поэтому повторно в `main` текст не рендерится.

**Проверено:** без этой строки `katex.min.css` не подключается ни на одной странице — формулы выводятся
без стилей, вперемешку HTML и MathML.

#### Почему KaTeX лежит в `static/`

Можно было подключить стили с CDN (`cdn.jsdelivr.net/npm/katex@…/dist/katex.min.css`). Здесь они лежат локально
(принцип 3 из главы 1): сайт не зависит от CDN, и посетитель не обращается к чужому серверу.

Первая строка `static/katex/katex.min.css`:

```css
/* KaTeX 0.18.4 (MIT), только woff2-шрифты */
```

**Версия CSS должна совпадать с версией KaTeX, встроенной в Hugo.** HTML генерирует Hugo, а CSS вы кладёте сами.
Если в новой версии KaTeX поменяются классы, а CSS останется старым, формулы поедут.
При обновлении Hugo проверяйте его версию KaTeX в примечаниях к выпуску и обновляйте `static/katex/`.

«Только woff2» — из стилей убраны старые форматы шрифтов (woff, ttf): woff2 поддерживают все современные браузеры, а файлов втрое меньше.

#### Альтернатива: формулы в браузере

Классический способ — подключить KaTeX или MathJax скриптом, и они найдут формулы на странице при загрузке.

| | При сборке (здесь) | В браузере |
|---|---|---|
| JavaScript у посетителя | нет | 100–300 КБ |
| Формула видна сразу | да | после загрузки скрипта страница «дёргается» |
| При выключенном JS | работает | сырой TeX |
| В RSS-ридере | MathML-часть, без стилей KaTeX | сырой TeX |
| Ошибки | видны при сборке | видны только на странице |

### Где ещё пригодится

Химические формулы пишутся там же: расширение KaTeX `mhchem` встроено. **Проверено:** `\(\ce{H2O}\)` рендерится без ошибки.
Опция `macros` тоже работает: **проверено** — с `"macros" (dict "\\R" "\\mathbb{R}")` формула `\(\R\)` выводится
как ℝ (`<mi mathvariant="double-struck">R`). А `.Store` — общий способ передать информацию из хука в шаблон:
так же можно подключать скрипт Mermaid, только если на странице есть блок ` ```mermaid `.

## Подсветка кода

### Как сделано здесь

В `hugo.yaml`:

```yaml
  highlight:
    noClasses: false
```

В `assets/css/syntax.css` (начало):

```css
/* Подсветка кода. Сгенерировано: hugo gen chromastyles --style=github / github-dark */

.chroma { background-color:#f7f7f7;-webkit-text-size-adjust:none; }
.chroma .err { color:#f6f8fa;background-color:#82071e }
```

и дальше (строка 75) тёмный вариант:

```css
@media (prefers-color-scheme: dark) {
  
  .chroma { color:#e6edf3;background-color:#0d1117;-webkit-text-size-adjust:none; }
```

### Разбор

Hugo раскрашивает код встроенной библиотекой [Chroma](https://github.com/alecthomas/chroma). Она разбивает код на токены
(ключевое слово, строка, комментарий) и оборачивает каждый в `<span>`.

**Проверено:** ` ```python ` даёт

```html
<div class=highlight><pre tabindex=0 class=chroma><code class=language-python data-lang=python><span class=line><span class=cl><span class=k>def</span> <span class=nf>hello</span><span class=p>():</span>
```

`k` — keyword, `nf` — name function, `p` — punctuation. Цвета классам задаёт `syntax.css`.

#### `noClasses`: классы или встроенные стили

- `noClasses: true` (по умолчанию в Hugo) — цвета пишутся прямо в `style="…"` каждого `<span>`. CSS-файл не нужен,
  но тема одна (`markup.highlight.style`, по умолчанию `monokai`) и не может меняться для тёмного режима.
  **Проверено:** с `true` появляется `<pre tabindex="0" style="color:#f8f8f2;background-color:#272822;…">` — тёмный monokai
  в светлой теме сайта.
- `noClasses: false` (здесь) — только классы, цвета — в отдельном CSS. Можно сделать две темы через медиазапрос, а HTML меньше.

#### `hugo gen chromastyles`: откуда `syntax.css`

CSS для классов генерирует сам Hugo:

```bash
hugo gen chromastyles --style=github > light.css
hugo gen chromastyles --style=github-dark > dark.css
```

`syntax.css` — это светлый файл как есть и тёмный, обёрнутый в `@media (prefers-color-scheme: dark) { … }`.
Список стилей с превью: [gohugo.io/quick-reference/syntax-highlighting-styles](https://gohugo.io/quick-reference/syntax-highlighting-styles/).
Полезные флаги: `--highlightStyle "bg:#fff3b0"` — цвет выделенных строк; `--mode dark` и `--modeSelector` —
для тем, переключаемых классом (`.dark .chroma`), а не медиазапросом.

Фон блоков кода в итоге задаёт не Chroma, а `main.css`: `pre, .chroma { background: var(--code-bg) !important; }` —
чтобы блоки кода были в палитре сайта (подробнее в главе 6).

#### Параметры блока кода

После названия языка в фигурных скобках можно передать параметры:

````markdown
```go {linenos=inline,hl_lines=[2]}
a := 1
b := 2
```
````

**Проверено:** у каждой строки появляется `<span class="ln">1</span>`, у второй — класс `line hl` (её фон задаёт `.chroma .hl`).

| Параметр | Что делает |
|---|---|
| `linenos=inline` / `table` / `false` | номера строк в строке или отдельной колонкой (`table` удобнее копировать) |
| `hl_lines=[2, "4-6"]` | выделить строки |
| `linenostart=10` | начать нумерацию с 10 |
| `anchorlinenos=true` | номера строк — ссылки-якоря |
| `style=dracula` | другая тема для одного блока (работает только при `noClasses: true`) |

Если язык не указан или Chroma его не знает, подсветки нет. **Проверено:** блок без языка даёт `<pre tabindex="0"><code>…`,
а ` ```nosuchlang ` — `<pre tabindex="0"><code class="language-nosuchlang" …>` без `<div class="highlight">`.

Глобальные умолчания (`lineNos`, `lineNumbersInTable`, `tabWidth`, `guessSyntax`) задаются в `markup.highlight` в `hugo.yaml`.
`guessSyntax: true` заставит Chroma угадывать язык у блоков без языка — угадывает он неточно.

`tabindex=0` у `<pre>` Hugo ставит сам: длинный код прокручивается вбок, и пользователь клавиатуры должен
иметь возможность сфокусировать блок и прокрутить его стрелками.

#### `renderer.unsafe`: сырой HTML в Markdown

```yaml
    renderer:
      unsafe: false
```

Markdown разрешает вставлять HTML-теги. Goldmark в Hugo по умолчанию их **выбрасывает**.

**Проверено:** `<div class="x">raw</div>` в тексте записи превращается в `<!-- raw HTML omitted -->`,
а при сборке появляется

```
WARN  Raw HTML omitted while rendering ".../content/posts/pervoe-obnovlenie/index.md"; see https://gohugo.io/getting-started/configuration-markup/#rendererunsafe
```

С `unsafe: true` HTML проходит как есть: можно вставить `<iframe>` с видео, `<details>`, `<video>`.
Минус — любой, кто пишет тексты, может вставить и `<script>`. Если тексты пишете только вы, `true` допустим.
В этом проекте нужные возможности даны безопасными способами (хуки, шорткоды), поэтому стоит `false`.

**Где ещё пригодится.** Вместо сырого HTML в Hugo используют **шорткоды**: `{{< youtube id >}}` — встроенный,
свои кладутся в `layouts/_shortcodes/имя.html`. Шорткод — шаблон, который владелец сайта вызывает из Markdown;
что именно выводится, решает шаблон, а не автор текста.

## Упражнения

1. Добавьте в `render-image.html` предупреждение о ненайденной картинке (см. «А если иначе» у `resolve-image.html`).
   Сломайте путь в демо-записи и убедитесь, что `make build` пишет `WARN`.
2. Сделайте в `img.html` адаптивную картинку с `srcset` на 720 и 1440 пикселей. В инструментах разработчика
   включите эмуляцию телефона и проверьте во вкладке «Сеть», какой файл загрузился.
3. Сравните размер `chart.png` в форматах `webp`, `webp drawing`, `webp lossless`, `avif`. Добавьте в `img.html` выбор
   спецификации: для PNG — `webp lossless`, для остального — `webp`.
4. Добавьте в `render-passthrough.html` макрос `\R` → `\mathbb{R}` через опцию `macros` и напишите формулу с ним.
5. Сгенерируйте `syntax.css` из стилей `catppuccin-latte` / `catppuccin-mocha` и сравните.
6. Сделайте `render-heading.html`, который добавляет к заголовкам `##` ссылку-якорь `#`.

## Итог

Render-хуки в `layouts/_markup/` заменяют стандартный вывод Markdown своим. Хук картинок через `resolve-image.html`
находит файл в бандле или в `assets/uploads/`, а `img.html` уменьшает его и переводит в WebP; отдельная картинка с title становится
`<figure>`. Формулы защищены от Markdown расширением passthrough и превращаются в HTML функцией `transform.ToMath` при сборке,
стили KaTeX подключаются только на страницах с формулами. Код раскрашивает Chroma классами, цвета для светлой и тёмной темы — в `syntax.css`.

Следующая глава: [Стили →](06-css.md)
