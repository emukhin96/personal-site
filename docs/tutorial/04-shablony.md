# Глава 4. Шаблоны

## Зачем

Шаблон — это HTML с «дырками», в которые Hugo подставляет данные: заголовок страницы, список записей,
имя из `data/site.yaml`. Для каждой страницы сайта Hugo выбирает шаблон, выполняет его и получает HTML.
В этой главе — язык шаблонов, правила, по которым Hugo выбирает шаблон, и разбор каждого шаблона проекта.

## Как сделано здесь

```
layouts/
├── baseof.html               каркас: <html>, <head>, шапка, <main>, подвал
├── home.html                 главная
├── page.html                 обычная страница (запасной вариант)
├── section.html              раздел (запасной вариант)
├── 404.html                  «Страница не найдена»
├── posts/
│   ├── page.html             запись
│   └── section.html          список всех записей по годам
├── projects/
│   ├── page.html             проект + хронология
│   └── section.html          список проектов
├── _partials/                куски, которые вставляются в другие шаблоны
│   ├── head.html             содержимое <head>                → глава 7
│   ├── header.html           шапка с навигацией
│   ├── footer.html           подвал
│   ├── post-list.html        список записей
│   ├── project-list.html     список проектов
│   ├── status.html           значок статуса проекта
│   ├── project-posts.html    функция: записи проекта
│   ├── post-projects.html    функция: проекты записи
│   ├── resolve-image.html    функция: путь → картинка          → глава 5
│   └── img.html              <img> с уменьшением и WebP       → глава 5
└── _markup/                  render-хуки Markdown              → глава 5
i18n/
└── ru.yaml                   «1 запись / 2 записи / 5 записей»
```

## Язык шаблонов

Hugo использует язык шаблонов из стандартной библиотеки Go (`text/template` и `html/template`) и добавляет к нему
сотни своих функций. Всё, что вне `{{ }}`, выводится как есть; всё внутри — код.

Примеры с пометкой **«Проверено»** выполнены в тестовом шаблоне на Hugo 0.169 с контентом этого проекта.

### `{{ }}` и обрезка пробелов

```go-html-template
<h1>{{ .Title }}</h1>
```

`{{ .Title }}` выводит заголовок текущей страницы.

Минус у скобки срезает все пробелы и переводы строк с этой стороны:

```go-html-template
[  {{ "a" }}  ]      → [  a  ]
[  {{- "a" -}}  ]    → [a]
```

**Проверено.** В шаблонах проекта почти каждая строка начинается с `{{-`: так в HTML не остаются пустые строки
от служебных тегов (`{{ with }}`, `{{ end }}`). На вид страницы это не влияет — браузер схлопывает пробелы, —
но HTML без них проще читать. Осторожно со строками текста: `{{ $a }} {{- $b }}` склеит два значения без пробела.

### Комментарии

```go-html-template
{{- /* Все записи, привязанные к проекту (по имени папки проекта), новые сверху. */}}
```

Комментарий `{{/* … */}}` не попадает в HTML, в отличие от `<!-- … -->`. Между `{{` и `/*` нельзя ставить ничего,
кроме `-` и одного пробела перед `/*` — иначе это ошибка разбора.

### Точка — текущий контекст

Точка `.` — «то, с чем шаблон сейчас работает». В шаблоне страницы это сама страница, поэтому `.Title`,
`.Date`, `.Params.summary`, `.Content` — её поля.

Точка **меняется** внутри `with` и `range`:

```go-html-template
{{ with .Params.summary }}<p>{{ . }}</p>{{ end }}   {{/* внутри with точка — это summary */}}
{{ range .Pages }}{{ .Title }}{{ end }}             {{/* внутри range точка — очередная страница */}}
```

`$` — точка «снаружи», то, что было передано шаблону в самом начале. Её используют, когда внутри `with`/`range`
нужна исходная страница:

```go-html-template
{{ with .Title }}{{ . }}/{{ $.Kind }}{{ end }}     → T/page
```

**Проверено.** В partial'е `$` — это аргумент partial'а, а не страница, с которой его вызвали.

### Переменные

```go-html-template
{{ $s := hugo.Data.site }}     {{/* объявить */}}
{{ $res = $res.Resize "…" }}   {{/* присвоить новое значение существующей */}}
```

Переменная видна до конца блока, в котором объявлена (`{{ end }}` закрывает блок):

```go-html-template
{{ $x := 1 }}{{ if true }}{{ $x = 2 }}{{ end }}{{ $x }}     → 2
{{ $y := 1 }}{{ if true }}{{ $y := 3 }}{{ end }}{{ $y }}    → 1
```

**Проверено.** Во втором случае `:=` внутри `if` создал **новую** переменную `$y`, которая исчезла на `{{ end }}`.
Это частая ошибка: хотели обновить значение в цикле, написали `:=`, а снаружи ничего не поменялось.
Отсюда правило: внутри `if`/`range` для уже объявленной переменной — `=`.

### `if`, `with`, `range`

```go-html-template
{{ if .IsHome }}…{{ else if .IsPage }}…{{ else }}…{{ end }}
```

`if` проверяет «истинность». Ложными считаются `false`, `0`, `nil`, пустая строка, пустой список, пустой словарь.

```go-html-template
{{ with .Params.summary }}<p class="summary">{{ . }}</p>{{ end }}
```

`with` = «если значение не пустое — выполни блок и сделай значение точкой». Это главный приём проекта:
необязательные поля выводятся только если заполнены, и не нужно писать `.Params.summary` дважды.
У `with` бывает `else` — он выполняется, если значение пустое (так сделан подвал, см. ниже).

```go-html-template
{{ range $i, $p := slice "а" "б" "в" }}{{ $i }}:{{ $p }} {{ end }}   → 0:а 1:б 2:в
{{ range slice }}x{{ else }}пусто{{ end }}                            → пусто
```

`range` перебирает список. С двумя переменными — индекс и элемент (для словаря — ключ и значение).
`else` — если список пуст. **Проверено.**

### Пайпы `|`

Результат слева передаётся последним аргументом функции справа:

```go-html-template
{{ .Date | time.Format ":date_long" }}     то же, что   {{ time.Format ":date_long" .Date }}
{{ $css := slice … | resources.Concat "css/site.css" | minify | fingerprint }}
```

Пайпы читаются слева направо, как конвейер, — поэтому ими удобно записывать цепочки обработки (глава 6).

### Логика: `and`, `or`, `not`, `eq`, `gt`, `cond`, `default`

| Выражение | Результат | Пояснение |
|---|---|---|
| `{{ or "" false "третье" }}` | `третье` | Первое «истинное» значение |
| `{{ and 1 "" 3 }}` | *(пусто)* | Первое «ложное» значение, или последнее, если все истинны |
| `{{ and 1 2 3 }}` | `3` | |
| `{{ cond true "да" "нет" }}` | `да` | Тернарный оператор: условие ? а : б |
| `{{ default "по умолчанию" "" }}` | `по умолчанию` | Второй аргумент пуст → первый |
| `{{ default "по умолчанию" "значение" }}` | `значение` | |
| `eq a b`, `ne`, `lt`, `le`, `gt`, `ge` | `true`/`false` | Сравнения: `gt (len .) 5` — «длина больше 5» |

**Проверено.** Тонкость: `and` и `or` вычисляют аргументы лениво (остановились на первом подходящем — остальные не вычисляются),
а `cond` — обычная функция, она вычисляет **оба** варианта. **Проверено:** `{{ cond true "ok" (errorf "…") }}`
роняет сборку, а `{{ or "x" (errorf "…") }}` — нет. Поэтому в `cond` не кладут дорогие или опасные выражения.

В проекте `or` даёт описание страницы с запасным вариантом (`head.html`):

```go-html-template
{{- $desc := or .Params.summary $s.description }}
```

а `cond` выбирает заголовок:

```go-html-template
{{- $title := cond .IsHome $s.name (printf "%s — %s" .Title $s.name) }}
```

### Списки и словари: `slice`, `dict`, `append`, `index`, `in`, `first`, `len`

```go-html-template
{{ slice "jpg" "png" }}                        список
{{ dict "url" "/posts/" "label" "Записи" }}    словарь: ключ, значение, ключ, значение…
{{ $s = $s | append 2 }}                       добавить в конец: [1] → [1 2]
{{ index (slice "a" "b") 1 }}                  → b    (элемент по номеру, с нуля)
{{ index (dict "k" "v") "k" }}                 → v    (значение по ключу)
{{ in (slice "jpg" "png") "png" }}             → true (есть ли элемент в списке)
{{ in "abc" "b" }}                             → true (есть ли подстрока)
{{ first 5 $pages }}                           первые 5 элементов
{{ len $pages }}                               количество
```

**Проверено.** Hugo не умеет изменять списки «на месте»: `append` возвращает новый список, его нужно присвоить
(`$out = $out | append .`). То же с `dict` — для изменения есть `merge`.

### `printf`

Форматирование строки по образцу: `%s` — строка, `%d` — целое число, `%q` — строка в кавычках, `%v` — что угодно.

```go-html-template
{{ printf "%s — %s" "a" "b" }}      → a — b
{{ printf "%dx webp" 1440 }}         → 1440x webp
```

**Проверено.** Второй пример — то, как `img.html` собирает параметры уменьшения картинки (глава 5).

### Страницы: `site.GetPage`, `site.RegularPages`, `.Pages`, `where`

- `site.GetPage "/projects/primer-proekta"` — найти страницу по пути в `content/`. Если её нет — `nil`, и `with` пропустит блок.
  **Проверено:** `site.GetPage "/projects/net-takogo"` → `nil`. Короткая форма `site.GetPage "primer-proekta"` тоже находит
  проект, но если у записи и проекта совпадут имена папок, результат неоднозначен — полный путь надёжнее.
- `site.RegularPages` — все обычные страницы (kind `page`) сайта: и записи, и проекты.
- `.Pages` у раздела — его страницы **и подразделы**. `.RegularPages` — только обычные страницы.
- `where КОЛЛЕКЦИЯ "ПОЛЕ" [ОПЕРАТОР] ЗНАЧЕНИЕ` — фильтр:

  ```go-html-template
  {{ where site.RegularPages "Section" "posts" }}                                   раздел = posts
  {{ where site.RegularPages "Params.projects" "intersect" (slice "primer-proekta") }}
  ```

  Операторы: `=` (по умолчанию), `!=`, `<`, `>`, `in`, `not in`, `intersect`, `like` (регулярное выражение).
  **`intersect`** — «у поля-списка есть хотя бы один общий элемент с данным списком». Это ровно то, что нужно:
  у записи `projects: [a, b]`, и она должна найтись и для `a`, и для `b`. **Проверено:** второй пример возвращает
  обе демо-записи. `in` здесь не подошёл бы: он проверяет, что **одно** значение поля входит в список.

### Сортировка и группировка

| Метод | Что делает |
|---|---|
| `.ByDate` | По дате, старые сначала |
| `.ByDate.Reverse` | По дате, новые сначала |
| `.ByWeight` | По `weight` (меньше — выше), без веса — в конце |
| `.ByTitle`, `.ByLastmod`, `.ByParam "status"` | По названию, дате изменения, любому параметру |
| `sort $pages "Params.started" "desc"` | Функция сортировки по любому полю |
| `.GroupByDate "2006"` | Группы по году: у группы `.Key` (год) и `.Pages` |

**Проверено:** `GroupByDate "2006"` на демо-записях даёт одну группу `2026(2)`, а `GroupByDate "January 2006"` —
две: `марта 2026(1)` и `января 2026(1)` (месяц в родительном падеже — Hugo форматирует по `locale`).

### Даты: `time.Format`

```go-html-template
{{ .Date | time.Format ":date_medium" }}
```

Hugo форматирует дату по образцу. Образец — либо готовый стиль с учётом языка, либо «эталонная дата» Go:
**2 января 2006, 15:04:05** — в образце пишут, как должна выглядеть именно эта дата.
**Проверено** на дате 7 мая 2026, 15:04, при `locale: ru-RU`:

| Образец | Результат | Где в проекте |
|---|---|---|
| `:date_short` | `07.05.26` | |
| `:date_medium` | `7 мая 2026 г.` | списки записей |
| `:date_long` | `7 мая 2026 г.` | страница записи, «Проект начат» |
| `:date_full` | `четверг, 7 мая 2026 г.` | |
| `"2006-01-02"` | `2026-05-07` | атрибут `datetime` у `<time>` |
| `"02.01.2006 15:04"` | `07.05.2026 15:04` | |
| `"January 2006"` | `мая 2026` | |
| `"Mon"` | `чт` | |

Заметьте: `:date_medium` сокращает месяц (`2 мар. 2026 г.`, `20 янв. 2026 г.` — так выглядят списки на сайте),
но «мая» сокращать некуда, поэтому в таблице он совпал с `:date_long`. Для машиночитаемого `datetime` всегда нужен
`"2006-01-02"` — его используют поисковики и читалки.

Ошибка новичков — писать образец как «ГГГГ-ММ-ДД» или `"2026-01-01"`: Go поймёт это буквально.
Только цифры эталонной даты: `2006` год, `01` месяц, `02` день, `15` часы, `04` минуты.

### Тексты интерфейса и склонения: `lang.Translate`, `i18n/ru.yaml`

```yaml
posts:
  one: "{{ .Count }} запись"
  few: "{{ .Count }} записи"
  many: "{{ .Count }} записей"
  other: "{{ .Count }} записи"
```

```go-html-template
{{ lang.Translate "posts" $n }}
```

В русском три формы множественного числа, и выбор зависит от последних цифр: 1, 21, 101 — «запись»;
2–4, 22–24 — «записи»; 0, 5–20, 25–30, 111 — «записей». Hugo знает эти правила (стандарт Unicode CLDR)
и выбирает ключ `one`, `few` или `many`; `other` — для дробных чисел. **Проверено:**

```
0 записей; 1 запись; 2 записи; 3 записи; 4 записи; 5 записей; 11 записей; 12 записей; 14 записей;
21 запись; 22 записи; 25 записей; 101 запись; 111 записей
```

Число передаётся вторым аргументом и доступно в строке как `{{ .Count }}`. Короткая форма — `{{ i18n "posts" $n }}`.

**А если иначе.** `{{ $n }} записей` с `if` на каждый случай — это 3 ветки и ошибки на 11–14. Если строк интерфейса станет
много или появится второй язык, все тексты («Проекты», «Хронология», «← раньше») стоит перенести в `i18n/` —
сейчас там только эта строка, остальные написаны прямо в шаблонах (сайт одноязычный).

### Markdown и HTML в шаблонах: `markdownify`, `plainify`

```go-html-template
{{ "**жирно** и *курсив*" | markdownify }}     → <strong>жирно</strong> и <em>курсив</em>
{{ "абзац 1\n\nабзац 2" | markdownify }}       → <p>абзац 1</p> <p>абзац 2</p>
{{ "<p>Текст с <b>тегами</b></p>" | plainify }} → Текст с тегами
```

**Проверено.** `markdownify` не оборачивает одну строку в `<p>`, а несколько абзацев — оборачивает.
Так в проекте выводятся `about` и `footer` из `data/site.yaml`. `plainify` убирает теги — нужен для
`<meta name="description">`, где HTML недопустим.

### Автоэкранирование: `safeHTML`, `safeURL`, `safeCSS`

Шаблоны Hugo знают, **куда** подставляется значение, и экранируют его под это место:

```go-html-template
{{ "<b>жирный</b>" }}                                → &lt;b&gt;жирный&lt;/b&gt;
{{ "<b>жирный</b>" | safeHTML }}                     → <b>жирный</b>
<a href="{{ "javascript:alert(1)" }}">               → <a href="#ZgotmplZ">
<a href="{{ "javascript:alert(1)" | safeURL }}">     → <a href="javascript:alert%281%29">
<style>a{color:{{ "red;}" }}}</style>                → <style>a{color:ZgotmplZ}</style>
```

**Проверено.** `ZgotmplZ` — метка «здесь было опасное значение, я его не вставил». Это защита от XSS:
даже если в поле админки окажется `<script>`, оно выведется как текст.

`safeHTML`, `safeURL`, `safeCSS` говорят «я доверяю этому значению». В проекте:

- `safeCSS` — для цвета акцента в `<style>` (`head.html`, глава 6): без него Hugo заменил бы значение на `ZgotmplZ`;
- `safeHTML` и `safeURL` — в render-хуке картинок (глава 5).

Используйте их только для значений, которые вы контролируете. Вывод `markdownify`, `.Content`,
`partial` уже помечен как безопасный HTML.

## Как Hugo выбирает шаблон

Для каждой страницы Hugo ищет шаблон от самого конкретного к самому общему. С версии 0.146 правила такие
(показаны только те, что встречаются в проекте):

| Страница | Порядок поиска |
|---|---|
| Главная (`home`) | `home.html` → `list.html` → `all.html` |
| Раздел `posts` (`section`) | `posts/section.html` → `section.html` → `list.html` → `all.html` |
| Запись (`page` в `posts`) | `posts/page.html` → `page.html` → `single.html` → `all.html` |
| Проект (`page` в `projects`) | `projects/page.html` → `page.html` → `single.html` → `all.html` |
| Страница 404 | `404.html` |

Плюс `layout: имя` во front matter: страница ищет `имя.html` (и `posts/имя.html`) раньше остальных.

**Проверено:**

- без `layouts/posts/page.html` записи рисуются общим `page.html` — без даты, обложки и «раньше / позже»;
- без всех `page.html` и `single.html` сборка печатает `WARN found no layout file for "html" for kind "page"`,
  а страницы записей пустые;
- без `section.html` и `posts/section.html` раздел записей берёт `list.html`, а если и его нет — `all.html`;
- страница с `layout: test` во front matter рисуется шаблоном `layouts/test.html`.

Поэтому в проекте общие `page.html` и `section.html` — запасные: они понадобятся, если появится новый раздел
(например, `content/talks/`) или отдельная страница (`content/about.md`), а свой шаблон для них ещё не написан.

**До 0.146** шаблоны назывались иначе: `_default/single.html`, `_default/list.html`, `index.html`, `partials/`.
Многие темы и статьи в интернете используют старые имена; Hugo их ещё понимает, но в новом проекте — только новые.

## Каркас: `baseof.html`, `define`, `block`

`layouts/baseof.html`:

```go-html-template
<!doctype html>
<html lang="{{ site.Language.Locale }}">
<head>
  {{- partial "head.html" . }}
</head>
<body>
  {{- partial "header.html" . }}
  <main class="wrap">
    {{- block "main" . }}{{ end }}
  </main>
  {{- partial "footer.html" . }}
</body>
</html>
```

`baseof.html` — общая обёртка для всех страниц. `{{ block "main" . }}…{{ end }}` объявляет «место», которое заполнит
конкретный шаблон. Шаблон страницы определяет его так:

```go-html-template
{{ define "main" }}
<article>…</article>
{{ end }}
```

Hugo берёт выбранный шаблон (например, `posts/page.html`), видит в нём `define "main"` и подставляет в `baseof.html`.

- Содержимое между `block "main" .` и `{{ end }}` — значение по умолчанию. **Проверено:** если написать там
  `<p>ЗАГЛУШКА</p>`, а в `404.html` переименовать блок, страница 404 покажет заглушку.
- Блоков может быть несколько: например, `{{ block "scripts" . }}{{ end }}` перед `</body>` для страниц со своими скриптами.
- `site.Language.Locale` — `ru-RU` из `hugo.yaml` (глава 2); атрибут `lang` нужен читалкам экрана и для переносов.

**А если опечатка в имени блока.** **Проверено:** если в `home.html` написать `define "mian"`, главная соберётся
без ошибок, но будет состоять только из шапки и подвала. Hugo не предупреждает о неиспользованных блоках.

Шаблон **без** `define` используется сам по себе, без `baseof.html` — так делают, например, для RSS или JSON.

## Partial'ы

Partial — кусок шаблона в `layouts/_partials/`, который вставляется вызовом:

```go-html-template
{{ partial "header.html" . }}
```

Второй аргумент — что станет точкой внутри partial'а. Передаётся **ровно один** аргумент, поэтому, когда нужно
несколько значений, их упаковывают в словарь:

```go-html-template
{{ partial "post-list.html" (dict "pages" . "hideProject" true) }}
```

и внутри обращаются к `.pages` и `.hideProject`.

Расширение `.html` можно не писать: **проверено**, `partial "status" .` работает так же, как `partial "status.html" .`.

### Partial как функция: `return`

Partial может не выводить HTML, а **вернуть значение** — список, страницу, число. Тогда он работает как функция:

```go-html-template
{{- return $posts.ByDate.Reverse }}
```

```go-html-template
{{- $posts := partial "project-posts.html" . }}
```

Так устроены `project-posts.html`, `post-projects.html` и `resolve-image.html`. Без `return` partial возвращает
выведенный текст — **проверено**: partial с текстом `  текст партиала  ` возвращает его вместе с пробелами
и переводом строки, а partial с `{{ return (slice 1 2 3) }}` — настоящий список, у которого `len` = 3.
В partial'е с `return` всё, что вне `{{ }}`, игнорируется.

**`partialCached`.** Partial выполняется при каждом вызове. `project-list.html` вызывает `project-posts.html`
для каждого проекта, а он перебирает все записи сайта. На десятках записей это незаметно; на тысячах можно
закешировать результат: `partialCached "project-posts.html" . .File.ContentBaseName` — третий аргумент — ключ кеша.

### `.Store`

У каждой страницы есть хранилище `.Store`, куда шаблоны могут положить значение для других шаблонов той же страницы:

```go-html-template
{{- $.Page.Store.Set "hasMath" true }}     {{/* render-хук формул */}}
{{- if .Store.Get "hasMath" }}             {{/* head.html */}}
```

Так `<head>` узнаёт, есть ли на странице формулы, и подключает стили KaTeX только тогда (подробно — глава 5).
Также есть `hugo.Store` (общее для всего сайта) и `newScratch` (локальное хранилище внутри шаблона).
Документация Hugo рекомендует `.Store` вместо старого `.Scratch` (**проверено:** в 0.169 `.Scratch` ещё работает и
предупреждений не печатает, но в новом коде его лучше не использовать).

## Разбор шаблонов проекта

### `_partials/header.html` — шапка

```go-html-template
{{- $cur := . }}
<header class="site-header wrap">
  <a class="brand" href="{{ "/" | relURL }}">{{ hugo.Data.site.name }}</a>
  <nav>
    {{- range slice (dict "url" "/projects/" "label" "Проекты" "section" "projects") (dict "url" "/posts/" "label" "Записи" "section" "posts") }}
    <a href="{{ .url | relURL }}"{{ if eq $cur.Section .section }} aria-current="page"{{ end }}>{{ .label }}</a>
    {{- end }}
  </nav>
</header>
```

- `$cur := .` — запоминаем страницу, потому что внутри `range` точка станет пунктом меню.
- Меню — список словарей прямо в шаблоне. Пунктов два, и они не меняются, поэтому нет смысла выносить их в настройки.
- `relURL` превращает путь в путь от корня сайта (с учётом подпапки из `baseURL` — с оговоркой из главы 2:
  путь с ведущим `/` подпапку не получает).
- `$cur.Section` — раздел текущей страницы: `posts` у списка записей и у каждой записи, `projects` — у проектов,
  пусто — у главной и 404. **Проверено:** `aria-current="page"` стоит у «Записей» на `/posts/` и на странице записи,
  у «Проектов» — на `/projects/` и на странице проекта, на главной и 404 — ни у кого.
- `aria-current="page"` — стандартный атрибут «это текущий раздел». Читалки экрана озвучивают его,
  а CSS (`nav a[aria-current]`) подсвечивает пункт. Отдельный класс `active` не нужен.

**А если иначе.** В Hugo есть встроенные меню: `menus:` в `hugo.yaml` или `menus: main` во front matter
`_index.md`, и в шаблоне `range site.Menus.main` с `.IsMenuCurrent`/`.HasMenuCurrent`. Это удобно, когда пунктов много
или их меняет владелец.

### `_partials/footer.html` — подвал

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

- `with … else` — если владелец написал свой подвал, выводится он (Markdown), иначе «© год имя».
- `now.Year` — год **в момент сборки**. Сайт пересобирается при каждой правке, так что год обновится с первой правкой в новом году.
- Ссылка на RSS не написана руками (`/posts/index.xml`), а получена у раздела: `.OutputFormats.Get "rss"`.
  Если RSS отключить (глава 2), ссылка исчезнет сама, а не будет вести в никуда.

### `home.html` — главная

```go-html-template
{{ define "main" }}
{{- $s := hugo.Data.site }}
<section class="intro">
  {{- with $s.avatar }}{{ with partial "resolve-image.html" (dict "path" .) }}
  {{- $a := .Fill "176x176 webp" }}
  <img class="avatar" src="{{ $a.RelPermalink }}" width="88" height="88" alt="">
  {{- end }}{{ end }}
  <div>
    <h1>{{ $s.name }}</h1>
    {{- with $s.tagline }}<p class="tagline">{{ . }}</p>{{ end }}
  </div>
</section>
{{- with $s.about }}<div class="about content">{{ . | markdownify }}</div>{{ end }}
{{- with $s.links }}
<ul class="links">
  {{- range . }}<li><a href="{{ .url }}"{{ if strings.HasPrefix .url "http" }} rel="me"{{ end }}>{{ .label }}</a></li>{{ end }}
</ul>
{{- end }}

{{- with site.GetPage "/projects" }}{{ with .Pages.ByWeight }}
<div class="section-head">
  <h2>Проекты</h2>
</div>
{{ partial "project-list.html" . }}
{{- end }}{{ end }}

{{- with site.GetPage "/posts" }}{{ with .Pages.ByDate.Reverse }}
<div class="section-head">
  <h2>Последние записи</h2>
  {{- if gt (len .) site.Params.homePostsLimit }}<a href="{{ "/posts/" | relURL }}">Все записи →</a>{{ end }}
</div>
{{ partial "post-list.html" (dict "pages" (first site.Params.homePostsLimit .)) }}
{{- end }}{{ end }}
{{ end }}
```

- Аватар: двойной `with` — «если путь задан» и «если картинка нашлась». `.Fill "176x176 webp"` — квадрат 176×176
  (вдвое больше показываемых 88×88 — для чётких экранов), подробно в главе 5. `alt=""` — фото декоративное, имя
  рядом уже написано текстом.
- `rel="me"` у внешних ссылок — подтверждение, что профиль ваш (так проверяют, например, Mastodon и IndieWeb).
  `strings.HasPrefix .url "http"` — не ставить его на `mailto:`.
- `with … .Pages.ByWeight` — блок «Проекты» появляется, только если есть хотя бы один проект: пустой список
  ложен для `with`. Удалите все проекты — исчезнет и заголовок.
- **`homePostsLimit`.** `first site.Params.homePostsLimit .` берёт первые 5 записей (новые сверху), а ссылка
  «Все записи →» появляется, только если записей больше лимита. **Проверено:** с лимитом 1 на главной
  одна запись и ссылка; с лимитом 5 — обе записи и ссылки нет.

**А если иначе.** `site.GetPage "/posts"` + `.Pages` вернёт и подразделы, если они когда-нибудь появятся
(`content/posts/2027/`). Строже — `where site.RegularPages "Section" "posts"`.

### `_partials/post-list.html` — список записей

```go-html-template
{{- /* .pages — записи; .hideProject — не показывать название проекта (на странице самого проекта). */}}
{{- $hide := .hideProject }}
<ul class="posts">
  {{- range .pages }}
  <li>
    <time datetime="{{ .Date.Format "2006-01-02" }}">{{ .Date | time.Format ":date_medium" }}</time>
    <div>
      <a href="{{ .RelPermalink }}">{{ .Title }}</a>
      {{- if not $hide }}{{ with partial "post-projects.html" . }}
      <span class="project">— {{ range $i, $p := . }}{{ if $i }}, {{ end }}{{ $p.Title }}{{ end }}</span>
      {{- end }}{{ end }}
    </div>
    {{- with .Params.summary }}<p class="summary">{{ . }}</p>{{ end }}
  </li>
  {{- end }}
</ul>
```

- Используется в трёх местах: главная, список записей, хронология проекта. Поэтому вынесен в partial.
- `$hide := .hideProject` — сохранить до `range`, потому что внутри точка станет записью.
  Если `hideProject` не передан, значение пустое, `not $hide` — истина, и проекты показываются.
- `.Date.Format "2006-01-02"` — метод даты (тот же образец, что у `time.Format`, но без учёта языка).
- `{{ if $i }}, {{ end }}` — запятая перед каждым элементом, кроме первого (`$i` = 0 — ложь). Стандартный приём
  для «а, б, в» без запятой в конце. Альтернатива — `delimit`, но он работает со строками, а здесь страницы.

### `_partials/post-projects.html` — проекты записи (функция)

```go-html-template
{{- /* Страницы проектов, к которым привязана запись. */}}
{{- $out := slice }}
{{- range .Params.projects }}
  {{- with site.GetPage (printf "/projects/%s" .) }}{{ $out = $out | append . }}{{ end }}
{{- end }}
{{- return $out }}
```

- На входе — запись, на выходе — список страниц-проектов.
- `printf "/projects/%s" .` — путь из имени папки (`primer-proekta` → `/projects/primer-proekta`).
- `with site.GetPage` — если такого проекта нет (опечатка, удалён, переименован), он молча пропускается.
  Так запись не ломает сборку, но и не сообщает об ошибке (глава 3, «Что будет при переименовании папки»).
  Если хочется узнавать о таких ошибках, добавьте `else`:

  ```go-html-template
  {{- with site.GetPage (printf "/projects/%s" .) }}…{{ else }}{{ warnf "%s: нет проекта %q" $.File.Path . }}{{ end }}
  ```

  **Проверено:** с опечаткой `primer-proektaa` в записи сборка печатает
  `WARN  posts/pervoe-obnovlenie/index.md: нет проекта "primer-proektaa"`.
- `$out = $out | append .` — именно `=`, а не `:=` (см. «Переменные»).
- Если `projects` — строка, а не список, `range` падает (**проверено** в главе 3).

### `_partials/project-posts.html` — записи проекта (функция)

```go-html-template
{{- /* Все записи, привязанные к проекту (по имени папки проекта), новые сверху. */}}
{{- $slug := .File.ContentBaseName }}
{{- $posts := where (where site.RegularPages "Section" "posts") "Params.projects" "intersect" (slice $slug) }}
{{- return $posts.ByDate.Reverse }}
```

- `.File.ContentBaseName` — имя папки проекта (`primer-proekta`). Это то же значение, что `:contentbasename` в адресе
  и что пишут записи в `projects`.
- Внутренний `where` — только записи. Внешний — те, у кого в `projects` есть этот адрес (`intersect`, см. выше).
- Возвращаются новые сверху — так их показывает хронология.

Это обратная сторона связи «запись → проекты»: связь хранится только в записи, а проект находит свои записи
поиском при сборке.

### `_partials/project-list.html` и `_partials/status.html`

```go-html-template
<ul class="projects">
  {{- range . }}
  {{- $n := len (partial "project-posts.html" .) }}
  <li>
    <a class="title" href="{{ .RelPermalink }}">{{ .Title }}</a>{{ partial "status.html" . }}
    {{- with .Params.summary }}<p>{{ . }}</p>{{ end }}
    {{- if $n }}<p class="meta">{{ lang.Translate "posts" $n }}</p>{{ end }}
  </li>
  {{- end }}
</ul>
```

```go-html-template
{{- $labels := dict "active" "в работе" "paused" "на паузе" "finished" "завершён" "archived" "в архиве" }}
{{- with .Params.status }}<span class="status status-{{ . }}">{{ index $labels . | default . }}</span>{{ end }}
```

- `project-list.html` получает список проектов как точку (`partial "project-list.html" .Pages.ByWeight`).
- `$n` — число записей проекта, «2 записи» выводится через `lang.Translate`; у проекта без записей строки нет.
- В `status.html` значение из front matter (`active`) переводится в подпись словарём.
  `index $labels . | default .` — если подписи нет, выводится само значение. **Проверено:** `status: testing`
  даёт `<span class="status status-testing">testing</span>` — без ошибки.
- Класс `status-{{ . }}` позволяет раскрасить статусы в CSS (сейчас выделен только `status-active`, глава 6).

**А если иначе.** Подписи статусов можно хранить в `i18n/ru.yaml` (`{{ i18n (printf "status_%s" .) }}`),
если появится второй язык.

### `posts/page.html` — запись и навигация «раньше / позже»

```go-html-template
{{ define "main" }}
{{- $projects := partial "post-projects.html" . }}
<article>
  <h1>{{ .Title }}</h1>
  <p class="meta">
    <time datetime="{{ .Date.Format "2006-01-02" }}">{{ .Date | time.Format ":date_long" }}</time>
    {{- with $projects }}<span>{{ range $i, $p := . }}{{ if $i }}, {{ end }}<a href="{{ $p.RelPermalink }}">{{ $p.Title }}</a>{{ end }}</span>{{ end }}
  </p>
  {{- with partial "resolve-image.html" (dict "page" . "path" .Params.cover) }}
  <div class="cover">{{ partial "img.html" (dict "res" . "alt" "" "eager" true) }}</div>
  {{- end }}
  <div class="content">{{ .Content }}</div>
</article>

{{- /* Навигация по хронологии первого проекта записи: старее / новее */}}
{{- with index $projects 0 }}
  {{- $project := . }}
  {{- $list := (partial "project-posts.html" .).ByDate }}
  {{- $prev := false }}{{ $next := false }}{{ $found := false }}
  {{- range $list }}
    {{- if eq .RelPermalink $.RelPermalink }}{{ $found = true }}
    {{- else if not $found }}{{ $prev = . }}
    {{- else if not $next }}{{ $next = . }}
    {{- end }}
  {{- end }}
  {{- if or $prev $next }}
<nav class="pager" aria-label="Записи проекта {{ $project.Title }}">
  {{- with $prev }}<a class="prev" href="{{ .RelPermalink }}"><small>← раньше</small>{{ .Title }}</a>{{ end }}
  {{- with $next }}<a class="next" href="{{ .RelPermalink }}"><small>позже →</small>{{ .Title }}</a>{{ end }}
</nav>
  {{- end }}
{{- end }}
{{ end }}
```

Верхняя часть: заголовок, дата, ссылки на проекты, обложка (глава 5), текст. `.Content` — тело записи,
уже превращённое в HTML.

Навигация — самая сложная логика в проекте:

1. `with index $projects 0` — берём **первый** проект записи. Если проектов нет, `index` вернёт `nil`,
   и навигации не будет. Если их несколько — навигация идёт по первому: «раньше / позже» в двух хронологиях
   сразу запутали бы читателя.
2. `$list` — записи этого проекта, **старые сначала** (`.ByDate`, без `.Reverse`).
3. Один проход по списку с тремя переменными-флагами:
   - пока текущая запись не найдена — каждая запись запоминается как `$prev` (в итоге это последняя перед текущей);
   - нашли текущую (`eq .RelPermalink $.RelPermalink` — сравнение адресов; `$` — это запись, точка — элемент списка) — `$found = true`;
   - первая запись после найденной — `$next`, дальше `not $next` ложно, и ничего не меняется.
4. `{{ $prev := false }}` — объявление до цикла, а внутри только `=`: иначе значения не вышли бы из `range`.
5. `aria-label` объясняет читалке экрана, что это за навигация.

**Проверено** на трёх записях одного проекта (январь, март, май): у январской — только «позже → Первое обновление»,
у мартовской — обе ссылки, у майской — только «← раньше».

**А если иначе: встроенные `.Next` и `.Prev`.** У коллекции страниц есть методы `$list.Next $` и `$list.Prev $`.
**Проверено:** на списке `.ByDate` (старые сначала) для мартовской записи `$list.Next $` вернул **январскую**,
а `$list.Prev $` — майскую. Hugo считает «следующей» страницу, стоящую в списке **перед** данной (так исторически
устроено для лент «новые сверху»). Код короче:

```go-html-template
{{- $prev := $list.Next $ }}{{ $next := $list.Prev $ }}
```

но названия перевёрнуты, и это легко перепутать. Цикл в проекте длиннее, зато читается однозначно.
Ещё есть `.PrevInSection` / `.NextInSection` — но они идут по всему разделу `posts`, а не по проекту.

### `posts/section.html` — все записи по годам

```go-html-template
{{ define "main" }}
<h1>{{ .Title }}</h1>
{{- with .Content }}<div class="content">{{ . }}</div>{{ end }}
{{- range .Pages.ByDate.Reverse.GroupByDate "2006" }}
<h2 class="year">{{ .Key }}</h2>
{{ partial "post-list.html" (dict "pages" .Pages) }}
{{- end }}
{{ end }}
```

- `.Title` и `.Content` — из `content/posts/_index.md`.
- `.Pages.ByDate.Reverse.GroupByDate "2006"` — новые сверху и сгруппированы по году. Внутри `range` точка — группа:
  `.Key` — «2026», `.Pages` — записи этого года.
- **А если иначе:** `GroupByDate "January 2006"` — по месяцам («марта 2026» — с родительным падежом, **проверено**;
  для заголовка лучше форматировать самостоятельно). Для очень длинного списка — постраничный вывод
  `.Paginate` и шаблон `_partials/pagination.html`.

### `projects/page.html` — проект с хронологией

```go-html-template
{{ define "main" }}
{{- $posts := partial "project-posts.html" . }}
<article>
  <h1>{{ .Title }} {{ partial "status.html" . }}</h1>
  {{- with .Params.summary }}<p class="lead">{{ . }}</p>{{ end }}
  {{- with .Params.links }}
  <ul class="links">
    {{- range . }}<li><a href="{{ .url }}">{{ .label }}</a></li>{{ end }}
  </ul>
  {{- end }}
  {{- with partial "resolve-image.html" (dict "page" . "path" .Params.cover) }}
  <div class="cover">{{ partial "img.html" (dict "res" . "alt" "" "eager" true) }}</div>
  {{- end }}
  {{- with .Content }}<div class="content">{{ . }}</div>{{ end }}
</article>

{{- with $posts }}
<h2>Хронология</h2>
{{ partial "post-list.html" (dict "pages" . "hideProject" true) }}
{{- end }}
{{- with .Params.started }}
<p class="meta" style="margin-top:2rem">Проект начат {{ . | time.Format ":date_long" }}</p>
{{- end }}
{{ end }}
```

- Всё необязательное — в `with`: нет ссылок, обложки, описания или записей — нет и блока.
- `hideProject true` — на странице проекта подпись «— Пример проекта» у каждой записи была бы лишней.
- `.Params.started` — дата из YAML; `time.Format` принимает и дату, и строку вида `2026-01-15`.
  **Проверено:** выводится «Проект начат 15 января 2026 г.».
- `style="margin-top:2rem"` — единственный встроенный стиль; при желании его можно перенести в `main.css`.

### `projects/section.html`, `section.html`, `page.html`, `404.html`

```go-html-template
{{ define "main" }}
<h1>{{ .Title }}</h1>
{{- with .Content }}<div class="content">{{ . }}</div>{{ end }}
<div style="margin-top:2rem">
{{ partial "project-list.html" .Pages.ByWeight }}
</div>
{{ end }}
```

`projects/section.html` — список проектов в порядке `weight`, тот же partial, что на главной.

`section.html` и `page.html` — запасные шаблоны (см. «Как Hugo выбирает шаблон»): заголовок, текст и простой список.

`404.html`:

```go-html-template
{{ define "main" }}
<h1>Страница не найдена</h1>
<p class="muted">Возможно, её переместили или удалили. <a href="{{ "/" | relURL }}">На главную →</a></p>
{{ end }}
```

Hugo собирает его в `public/404.html`, а веб-сервер отдаёт его с кодом 404 на любой несуществующий адрес
(`handle_errors` в Caddyfile, глава 10). Он тоже использует `baseof.html`, так что шапка и подвал на месте.

## Где ещё пригодится

- `where … "intersect"` — фильтр по любому полю-списку: теги, авторы, технологии проекта.
- Partial с `return` — любая повторяющаяся «вычислительная» логика: поиск связанных страниц, разбор пути картинки,
  подсчёт времени чтения.
- `with … else` — вывод значения с запасным вариантом, без дублирования кода.
- `lang.Translate` со счётчиком — «5 минут чтения», «3 проекта», «12 комментариев».
- Однопроходный цикл с флагами — любые «соседи» элемента в списке: предыдущая/следующая глава книги,
  соседние фото в галерее.

## Упражнения

1. Добавьте в `post-list.html` вывод года рядом с датой только для записей не текущего года (подсказка: `now.Year`, `.Date.Year`).
2. Напишите partial `reading-time.html`, который возвращает «N минут чтения» по `.WordCount` (200 слов в минуту),
   с правильным склонением через `i18n/ru.yaml`. Выведите его в `posts/page.html`.
3. Добавьте в `post-projects.html` предупреждение `warnf` о несуществующем проекте и проверьте его опечаткой в записи.
4. Перепишите навигацию «раньше / позже» на `$list.Next` / `$list.Prev` и убедитесь, что результат тот же.
5. Сделайте страницу `content/about.md` и посмотрите, какой шаблон её рисует. Создайте для неё свой.

## Итог

Шаблоны Go: `{{ }}` с точкой-контекстом, `with` для необязательных значений, `range` для списков, переменные с
`:=`/`=`, пайпы для цепочек. Hugo выбирает шаблон от конкретного (`posts/page.html`) к общему (`page.html`,
`single.html`, `all.html`) и вставляет его блок `main` в `baseof.html`. Повторяющийся HTML вынесен в partial'ы,
а логика — в partial'ы с `return`. Связь «запись → проекты» читается в обе стороны двумя функциями:
`post-projects.html` (по полю записи) и `project-posts.html` (поиском по всем записям).

Следующая глава: [Картинки, формулы, код →](05-kartinki-formuly-kod.md)
