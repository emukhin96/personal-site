# Глава 6. Стили

## Зачем

Стили отвечают за то, как сайт читается: ширина колонки, размер и межстрочный интервал текста, цвета,
тёмная тема, поведение на телефоне. Здесь их немного: `assets/css/main.css` — около 200 строк, `assets/css/syntax.css` —
цвета подсветки кода (глава 5).

Требования:

- текст удобно читать и на телефоне, и на большом мониторе;
- тёмная тема включается сама, если она включена в системе;
- цвет акцента владелец меняет в админке, не трогая CSS;
- после изменения стилей посетители сразу получают новый файл, но старый при этом кешируется надолго.

Никаких CSS-фреймворков, препроцессоров и веб-шрифтов: обычный CSS, который понимают все современные браузеры.

## Как сделано здесь

CSS подключается в `layouts/_partials/head.html`:

```go-html-template
{{- $css := slice (resources.Get "css/syntax.css") (resources.Get "css/main.css") | resources.Concat "css/site.css" | minify | fingerprint }}
<link rel="stylesheet" href="{{ $css.RelPermalink }}" integrity="{{ $css.Data.Integrity }}">
{{- with $s.accent }}
<style>:root{--accent:{{ . | safeCSS }}}</style>
{{- end }}
```

**Проверено:** на сайте это превращается в

```html
<link rel=stylesheet href=/css/site.min.a2d27922b00a5702bae0dd70399336cc93ddc05cdb91f200b79328c3c31037cf.css integrity="sha256-otJ5IrAKVwK64N1wOZM2zJPdwFzbkfIAt5Mow8MQN88="><style>:root{--accent:#2563eb}</style>
```

Сначала разберём сборку CSS, потом — сам `main.css` сверху вниз.

## Сборка CSS через Hugo Pipes

**Hugo Pipes** — обработка файлов из `assets/` при сборке: склеить, сжать, добавить хеш, скомпилировать SCSS, собрать JS.
Каждая функция принимает ресурс и возвращает новый, поэтому их удобно соединять через `|` (глава 4).

| Шаг | Что делает |
|---|---|
| `resources.Get "css/main.css"` | Читает `assets/css/main.css` как ресурс. Нет файла — возвращает `nil` |
| `slice a b` | Список из двух ресурсов. Порядок важен: `syntax.css` первым, чтобы `main.css` мог переопределить его правила |
| `resources.Concat "css/site.css"` | Склеивает список в один файл с этим именем |
| `minify` | Убирает пробелы, комментарии, сокращает цвета. **Проверено:** 11986 → 9717 байт |
| `fingerprint` | Добавляет к имени SHA-256 содержимого: `site.min.a2d2…37cf.css`. Записывает хеш в `.Data.Integrity` |
| `.RelPermalink` | Адрес файла от корня сайта. В этот момент Hugo и записывает файл в `public/` |

### Почему один файл

Один запрос вместо двух. Для сайта такого размера это мелочь, но разница заметна на медленной мобильной сети:
каждый CSS-файл блокирует отрисовку, пока не загрузится.

### Зачем хеш в имени

Браузер кеширует CSS. Вопрос: на сколько?

- **Надолго** — посетители не увидят новые стили, пока не истечёт кеш.
- **Ненадолго** — браузер на каждой странице переспрашивает сервер, не изменился ли файл.

Хеш в имени снимает выбор. Содержимое поменялось — поменялось имя, HTML ссылается на новый файл, а у старого имени
содержимое не меняется никогда. Поэтому Caddy отдаёт такие файлы с `Cache-Control: public, max-age=31536000, immutable`
(`deploy/Caddyfile`, глава 10): кешировать на год и даже не переспрашивать.

### `integrity`: защита от подмены

Атрибут `integrity="sha256-…"` (Subresource Integrity, SRI) говорит браузеру: применяй файл, только если его хеш совпал.
Если файл подменили по дороге или на сервере, стили не применятся.

**Проверено:** после дописывания одного комментария в CSS-файл на сервере браузер пишет в консоль
`Failed to find a valid digest in the 'integrity' attribute for resource '…site.min.a2d2…css' with computed SHA-256`,
и страница остаётся без стилей (фон `body` — прозрачный).

Для своих файлов на своём сервере SRI — подстраховка. По-настоящему он нужен, когда файл грузится с чужого CDN.

### Почему `assets/`, а не `static/`

Файлы из `static/` копируются в `public/` как есть, Hugo их не читает. Если положить CSS туда:

```html
<link rel="stylesheet" href="/css/main.css">
```

- нет минификации и склейки;
- нет хеша — придётся выбирать между долгим кешем (старые стили у посетителей) и коротким (лишние запросы);
- нет `integrity`.

**Проверено:** если убрать `| minify | fingerprint`, на сайте появляется `/css/site.css` (11986 байт) без хеша в имени.

### А если иначе

- **Нет файла.** `resources.Get` вернёт `nil`, и `resources.Concat` упадёт.
  **Проверено:** `error calling Concat: expected slice of Resource objects, received …` — сборка останавливается.
  Это хорошо: опечатку в имени файла видно сразу.
- **`fingerprint "md5"`** — другой алгоритм хеша, имя короче. Для SRI браузеры принимают sha256/384/512,
  поэтому оставьте значение по умолчанию.
- **Встроить CSS прямо в HTML**: `<style>{{ $css.Content | safeCSS }}</style>`. Нет лишнего запроса, но CSS скачивается
  заново с каждой страницей. Так делают для «критического» CSS первого экрана.

### Где ещё пригодится

- **`css.Build`** — сборка CSS через esbuild, встроенный в Hugo: разворачивает `@import`, переводит вложенные правила
  в обычные для старых браузеров. **Проверено** на Hugo 0.169: `.a{color:red; & .b{color:blue}}` с
  `css.Build (dict "minify" true "target" "chrome100")` превращается в `.a{color:red}.a .b{color:#00f}`, а без `target`
  вложенность остаётся как есть. С ним можно держать стили в нескольких файлах и подключать их через `@import`.
- **SCSS** — `resources.Get "scss/main.scss" | css.Sass`. Переменные, миксины, вложенность. Нужен Hugo extended
  (встроенный LibSass — устаревший) или установленный Dart Sass (`"transpiler" "dartsass"`).
- **Tailwind CSS** — `css.TailwindCSS`. Нужен установленный через npm `@tailwindcss/cli`, а значит Node.js в CI.
  Противоречит принципу «один исполняемый файл» (глава 1), поэтому здесь не используется.
- **JavaScript** — `js.Build` (тот же esbuild): собрать и сжать скрипты, если они появятся.

## Разбор `main.css`

### Переменные и цвет акцента

```css
/* --accent задаётся из data/site.yaml (Настройки сайта → Цвет акцента) */
:root {
  --accent: #2563eb;
  --bg: #fdfdfc;
  --fg: #1c1c1a;
  --muted: #6b6b66;
  --line: #e7e6e2;
  --code-bg: #f4f3f0;
  --link: var(--accent);
  --radius: 6px;
  --measure: 40rem;
  color-scheme: light dark;
}
```

**CSS-переменные** (custom properties) объявляются как `--имя: значение` и читаются как `var(--имя)`.
`:root` — корневой элемент `<html>`; объявленное там видно во всём документе. Все цвета и размеры собраны в одном месте:
сменить фон — одна строка.

Цвет акцента владелец задаёт в админке (`accent` в `data/site.yaml`). CSS-файл общий и закеширован на год,
поэтому подставить значение в него нельзя. Вместо этого `head.html` пишет в каждую страницу маленький `<style>`:

```html
<style>:root{--accent:#2563eb}</style>
```

Он идёт после `<link>`, поэтому переопределяет `--accent` из файла. А раз `--link: var(--accent)`, вслед за ним меняются
цвет ссылок и значок статуса «в работе».

**Зачем `safeCSS`.** Шаблонизатор Go проверяет значения, которые вставляются внутрь `<style>`. Простые значения вроде `#2563eb`
он пропускает, а сложные считает подозрительными и заменяет на `ZgotmplZ` (маркер «вставка заблокирована»).
**Проверено:** с `accent: 'oklch(60% 0.2 260)'` и без `safeCSS` выходит `<style>:root{--accent:ZgotmplZ}`, а с `safeCSS` —
`<style>:root{--accent:oklch(60% 0.2 260)}`. `safeCSS` отключает проверку. Это допустимо, потому что значение задаёт
владелец через админку, а не посетитель. Если бы его мог ввести кто угодно, через `;}body{display:none` можно было бы
сломать страницу.

`--measure: 40rem` — ширина колонки текста. `rem` — размер шрифта корневого элемента (обычно 16px), то есть 640px.
**Проверено** в Chromium: в колонке шириной 600px (640 минус поля по 20px) шрифтом 17px помещается около 57 символов
русского текста в строке. Типографы советуют 45–75 символов: короче — глаз часто прыгает на новую строку, длиннее — теряет строку
при переходе.

`color-scheme: light dark` сообщает браузеру, что страница поддерживает обе схемы. Тогда браузер сам перекрашивает то,
что рисует он: полосы прокрутки, поля форм, фон до загрузки CSS.

### Тёмная тема

```css
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #141413;
    --fg: #e8e7e3;
    --muted: #9a9993;
    --line: #2c2c2a;
    --code-bg: #1d1d1b;
    /* Тот же акцент, но светлее — чтобы ссылки читались на тёмном фоне */
    --link: color-mix(in oklab, var(--accent) 65%, white);
  }
}
```

`prefers-color-scheme: dark` срабатывает, если в системе (или браузере) включена тёмная тема. Внутри переопределены только
переменные — остальной CSS не меняется. В этом главная польза переменных: тема — это набор значений, а не копия всех правил.

Фон не чисто чёрный (`#141413`), а текст не чисто белый (`#e8e7e3`): максимальный контраст на тёмном фоне утомляет глаза.

`color-mix(in oklab, var(--accent) 65%, white)` — смесь: 65% акцента и 35% белого. Синий `#2563eb` хорошо виден на светлом
фоне, но на тёмном почти сливается. Владелец может выбрать любой акцент, поэтому подобрать светлый вариант вручную нельзя —
CSS вычисляет его сам. `in oklab` — пространство, в котором смешивают: в OKLab смесь выглядит равномерной по яркости
(в `srgb` она получается грязноватой).

**Проверено** в Chromium: в тёмной теме цвет ссылки — `oklab(0.70 -0.017 -0.139)` (заметно светлее исходного синего),
фон — `rgb(20, 20, 19)`, фон кода — `rgb(29, 29, 27)`.

**А если иначе:**

- `color-mix(in srgb, …)` — то же, но цвета смешиваются как RGB-числа; вид другой, чуть менее насыщенный.
- Пропорция `80%` — ссылки ближе к исходному цвету и хуже читаются; `50%` — почти пастельные.
- Браузер без `color-mix` (выпущенный до 2023 года) не поймёт значение, и `color` у ссылок станет унаследованным —
  ссылки будут цвета текста. Подстраховка — объявить `--link` дважды: сначала простым цветом, затем через `color-mix`.

**Модификация: переключатель темы.** Сейчас тема следует за системой. Чтобы дать кнопку, нужен JavaScript:

```css
:root[data-theme="dark"] { --bg: #141413; /* … те же значения */ }
```

```html
<button onclick="
  const t = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
  document.documentElement.dataset.theme = t;
  localStorage.setItem('theme', t);
">Тема</button>
<script>
  // В <head>, до CSS: применить сохранённый выбор раньше первой отрисовки, иначе страница мигнёт
  const t = localStorage.getItem('theme'); if (t) document.documentElement.dataset.theme = t;
</script>
```

Плюс медиазапрос нужно ограничить: `@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { … } }`.
А `syntax.css` — пересобрать с `--modeSelector`, чтобы подсветка тоже слушалась атрибута (глава 5).
Это противоречит принципу «без JS у посетителя», поэтому в проекте переключателя нет.

### Основа

```css
*, *::before, *::after { box-sizing: border-box; }

html {
  -webkit-text-size-adjust: 100%;
  text-size-adjust: 100%;
}

body {
  margin: 0;
  background: var(--bg);
  color: var(--fg);
  font: 17px/1.65 system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
  font-kerning: normal;
}
```

- **`box-sizing: border-box`** — ширина элемента включает поля и рамку. По умолчанию (`content-box`) `width: 100%` плюс
  `padding: 1rem` дают элемент шире родителя и горизонтальную прокрутку. Почти во всех современных CSS-сбросах есть эта строка.
- **`text-size-adjust: 100%`** — запрещает мобильному Safari и Chrome «на глаз» увеличивать шрифт в некоторых блоках
  при повороте телефона. Вариант с `-webkit-` — для старых версий Safari.
- **`font: 17px/1.65 …`** — сокращённая запись: размер 17px, межстрочный интервал 1.65 (без единиц — множитель от размера
  шрифта, правильно наследуется). Сокращение `font` сбрасывает все остальные свойства шрифта (`font-weight`, `font-style`)
  в начальные значения — для `body` это и нужно.
- **Системный стек шрифтов.** `system-ui` — шрифт интерфейса ОС: San Francisco на Mac и iPhone, Segoe UI на Windows,
  Roboto на Android. Остальные имена — запасные для старых браузеров. Шрифты не скачиваются: 0 байт и 0 запросов, текст появляется
  сразу. Минус — сайт выглядит немного по-разному в разных системах.
- **`font-kerning: normal`** — включить кернинг (поправки расстояний между парами букв). Браузеры часто отключают его
  на мелком тексте ради скорости.

**А если иначе: свой шрифт.** Положите `.woff2` в `static/fonts/` и подключите:

```css
@font-face {
  font-family: "Inter";
  src: url("/fonts/Inter.woff2") format("woff2");
  font-display: swap; /* показать текст системным шрифтом, пока грузится свой */
}
body { font-family: "Inter", system-ui, sans-serif; }
```

Это +100–300 КБ и мелькание шрифта при загрузке. Google Fonts по CDN — ещё и обращение к стороннему серверу
(противоречит принципу 3 из главы 1).

### Колонка, ссылки, заголовки

```css
.wrap {
  max-width: var(--measure);
  margin: 0 auto;
  padding: 0 1.25rem;
}

a { color: var(--link); text-underline-offset: 0.18em; text-decoration-thickness: 1px; }
a:hover { text-decoration-thickness: 2px; }

h1, h2, h3 { line-height: 1.25; letter-spacing: -0.01em; }
h1 { font-size: 1.9rem; margin: 0 0 0.5rem; }
h2 { font-size: 1.3rem; margin: 2.5rem 0 1rem; }
h3 { font-size: 1.1rem; margin: 2rem 0 0.75rem; }

img { max-width: 100%; height: auto; border-radius: var(--radius); }

hr { border: 0; border-top: 1px solid var(--line); margin: 2.5rem 0; }
```

- **`.wrap`** — класс шапки, `<main>` и подвала. `max-width` вместо `width`: на узком экране колонка сужается сама.
  `margin: 0 auto` — по центру. `padding` — поля, чтобы текст не прилипал к краям телефона.
- **`text-underline-offset`** — подчёркивание чуть ниже букв, не пересекает «у», «р», «д». `text-decoration-thickness`
  при наведении — заметная, но спокойная обратная связь.
- **Заголовки.** Межстрочный интервал меньше, чем у текста: в крупных строках 1.65 смотрится слишком разреженно.
  `letter-spacing: -0.01em` — чуть плотнее, крупный текст визуально «разваливается». Отступ сверху у `h2` больше, чем снизу:
  заголовок ближе к своему тексту, чем к предыдущему.
- **`img { max-width: 100%; height: auto; }`** — картинка не вылезает из колонки, а высота пересчитывается по пропорциям
  из атрибутов `width`/`height` (глава 5). Без `height: auto` картинка с атрибутом `height` растянулась бы по вертикали.

### Шапка и подвал: flexbox

```css
.site-header {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  justify-content: space-between;
  gap: 0.5rem 1.5rem;
  padding-top: 2rem;
  padding-bottom: 3rem;
}
.site-header .brand { color: var(--fg); font-weight: 600; text-decoration: none; }
.site-header nav { display: flex; gap: 1.25rem; }
.site-header nav a { color: var(--muted); text-decoration: none; }
.site-header nav a:hover,
.site-header nav a[aria-current] { color: var(--fg); }
```

- `display: flex` + `justify-content: space-between` — имя слева, меню справа.
- `flex-wrap: wrap` — если не помещаются в одну строку (длинное имя на узком экране), меню переносится вниз, а не сжимается.
- `align-items: baseline` — выравнивание по базовой линии текста: имя (жирное) и пункты меню стоят на одной линии.
- `gap: 0.5rem 1.5rem` — промежутки: 0.5rem между строками, 1.5rem между элементами в строке. Раньше для этого
  писали `margin` у детей и отменяли у последнего.
- **`a[aria-current]`** — селектор по атрибуту. `header.html` ставит `aria-current="page"` на пункт текущего раздела (глава 4).
  Один атрибут работает дважды: экранный диктор говорит «текущая страница», а CSS выделяет пункт. Отдельный класс `.active`
  не нужен.

Подвал (`.site-footer`) устроен так же: `flex`, `wrap`, `space-between`, текст `--muted` и рамка сверху `--line`.
`.site-footer a { color: inherit; }` — ссылка RSS цвета подвала, а не акцента.

### Главная

```css
.intro { display: flex; gap: 1.5rem; align-items: flex-start; }
.intro .avatar { flex: none; width: 88px; height: 88px; border-radius: 50%; object-fit: cover; }
.intro .tagline { color: var(--muted); font-size: 1.1rem; margin: 0; }
.about { margin-top: 1.5rem; }
@media (max-width: 30rem) {
  .intro { flex-direction: column; gap: 1rem; }
}

.links { display: flex; flex-wrap: wrap; gap: 0.5rem 1.25rem; padding: 0; margin: 1rem 0 0; list-style: none; }
```

- **`flex: none`** у аватара — не сжиматься, когда имя длинное. Без этого flex ужал бы картинку в овал.
- **`object-fit: cover`** — если картинка не квадратная, заполнить круг, обрезав края (CSS-аналог `.Fill` из главы 5).
  Здесь Hugo уже обрезал её в квадрат 176×176, так что это подстраховка.
- Файл 176×176, а выводится 88×88 — вдвое больше для чёткости на экранах с плотностью 2×.
- **`@media (max-width: 30rem)`** — на экранах уже 480px аватар встаёт над именем. Медиазапрос в `rem` (а не в `px`)
  срабатывает с учётом размера шрифта: если пользователь увеличил шрифт в браузере, раскладка перестроится раньше.
- **`.links`** — список ссылок в строку: сброшены отступы и маркеры у `<ul>`. Ссылки остались списком в HTML,
  и большинство экранных дикторов скажут «список, 3 элемента». Исключение — VoiceOver в Safari: `<ul>` с `list-style: none`
  он списком не считает. Если это важно, добавьте `role="list"` к `<ul>`.

### Списки записей: grid

```css
.posts { list-style: none; padding: 0; margin: 0; }
.posts li { display: grid; grid-template-columns: 7.5rem 1fr; gap: 0 1rem; padding: 0.4rem 0; }
.posts time { color: var(--muted); font-variant-numeric: tabular-nums; font-size: 0.95rem; padding-top: 0.05em; }
.posts .project { color: var(--muted); font-size: 0.9rem; }
.posts .summary { grid-column: 2; color: var(--muted); font-size: 0.95rem; margin: 0.1rem 0 0; }
@media (max-width: 30rem) {
  .posts li { grid-template-columns: 1fr; }
  .posts .summary { grid-column: 1; }
}
```

Каждая запись — строка из двух колонок: дата и заголовок. HTML (`_partials/post-list.html`):

```html
<li>
  <time …>2 мар. 2026 г.</time>
  <div><a …>Первое обновление</a> …</div>
  <p class="summary">…</p>
</li>
```

- **`grid-template-columns: 7.5rem 1fr`** — первая колонка фиксированной ширины (влезает «20 янв. 2026 г.»),
  вторая — всё остальное место (`1fr` — одна доля свободного пространства). Даты стоят ровной колонкой, заголовки начинаются
  на одной вертикали.
- **`.summary { grid-column: 2 }`** — третий элемент сам перенёсся бы в первую колонку следующей строки.
  `grid-column: 2` ставит его под заголовком.
- **На телефоне** — одна колонка: дата над заголовком.

**Проверено** в Chromium: при ширине окна 1280 вычисленные колонки — `120px 464px`, при 375 — `335px`.

- **`font-variant-numeric: tabular-nums`** — цифры одинаковой ширины. В обычном режиме «1» уже «8», и даты в колонке
  стоят неровно.

**А если иначе.** На flexbox это сделать сложнее: колонка дат выровнялась бы только при фиксированной ширине `<time>`,
а перенос подзаголовка под заголовок потребовал бы ещё одной обёртки. Grid решает двумерную раскладку, flex — одномерную.

### Мета-строка и «сова»

```css
.muted { color: var(--muted); }
.meta { color: var(--muted); font-size: 0.95rem; }
.meta > * + *::before { content: "·"; margin: 0 0.5em; }
```

Под заголовком записи — дата и проекты: `<p class="meta"><time>…</time><span>Пример проекта</span></p>`.
Между ними нужна точка-разделитель, но только **между**: не перед первым и не после последнего.

Селектор `* + *` («лоботомированная сова» — так его прозвали за вид) выбирает каждый элемент, перед которым есть
соседний элемент, то есть все, кроме первого. `.meta > * + *::before` — псевдоэлемент перед каждым непервым ребёнком.

**Проверено** в Chromium: у `<time>` `::before` — `none`, у `<span>` — `"·"`. Если у записи нет проекта, `<span>` нет,
и точка не появляется — шаблону не нужно об этом думать.

Где ещё пригодится: `.stack > * + * { margin-top: 1rem; }` — равные отступы между блоками без лишнего отступа сверху.

### Проекты и значок статуса

```css
.projects { list-style: none; padding: 0; margin: 0; }
.projects li { padding: 1rem 0; border-top: 1px solid var(--line); }
.projects li:last-child { border-bottom: 1px solid var(--line); }
.projects .title { font-weight: 600; margin-right: 0.5rem; }
.projects p { margin: 0.25rem 0 0; }

.status {
  display: inline-block;
  font-size: 0.75rem;
  line-height: 1;
  padding: 0.3em 0.55em;
  border: 1px solid var(--line);
  border-radius: 999px;
  color: var(--muted);
  vertical-align: 0.15em;
}
.status-active { color: var(--link); border-color: currentColor; }
```

- Линии между проектами: рамка сверху у каждого и снизу у последнего (`:last-child`).
- **`border-radius: 999px`** — «таблетка»: радиус больше половины высоты всегда даёт полукруглые торцы, при любом размере.
- **`padding` в `em`** — отступы растут вместе с шрифтом значка.
- **`vertical-align: 0.15em`** — поднять значок, чтобы мелкий текст был по центру строки с крупным заголовком.
- **`border-color: currentColor`** — рамка цвета текста. У «в работе» и текст, и рамка цвета ссылок.
  Классы `status-paused`, `status-finished` и `status-archived` шаблон тоже ставит (`_partials/status.html`), но в CSS их нет —
  они выглядят как базовый `.status`. Захотите свой цвет для каждого статуса — добавьте правила.

### Статья

```css
.lead { font-size: 1.15rem; color: var(--muted); margin: 0.75rem 0 0; }
.cover { margin: 2rem 0 0; }
.content { margin-top: 2rem; }
.content > :first-child { margin-top: 0; }
.content figure { margin: 2rem 0; }
.content figcaption { color: var(--muted); font-size: 0.9rem; margin-top: 0.5rem; text-align: center; }
.content blockquote { margin: 1.5rem 0; padding-left: 1rem; border-left: 3px solid var(--line); color: var(--muted); }
.content table { border-collapse: collapse; width: 100%; display: block; overflow-x: auto; }
.content th, .content td { border-bottom: 1px solid var(--line); padding: 0.4rem 0.75rem 0.4rem 0; text-align: left; }
.content .katex-display { overflow-x: auto; overflow-y: hidden; padding: 0.25rem 0; }
```

- **`.content`** — контейнер текста из Markdown. Стили привязаны к нему, а не к тегам глобально: `blockquote` или `table`
  в других местах сайта не изменятся.
- **`.content > :first-child { margin-top: 0; }`** — если текст начинается с `<h2>`, его большой верхний отступ сложился бы
  с отступом `.content`.
- **Таблицы и формулы с прокруткой.** Широкая таблица или формула не помещается в колонку на телефоне. `overflow-x: auto`
  даёт прокрутку только этому блоку, а не всей странице. У таблицы для этого нужен `display: block`: у обычной таблицы
  `overflow` не работает. Минус — таблица перестаёт растягиваться на всю ширину, если она узкая.
  `.katex-display` — класс блочной формулы из KaTeX (глава 5). `overflow-y: hidden` убирает вертикальную полосу, которая
  иногда появляется из-за выступающих символов.

### Код

```css
code, pre { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace; font-size: 0.88em; }
:not(pre) > code { background: var(--code-bg); padding: 0.12em 0.35em; border-radius: 4px; }
pre, .chroma { background: var(--code-bg) !important; }
pre { padding: 1rem 1.1rem; overflow-x: auto; border-radius: var(--radius); line-height: 1.5; }
.highlight { margin: 1.5rem 0; }
.highlight pre { margin: 0; }
```

- **`ui-monospace`** — системный моноширинный шрифт (SF Mono на Mac), дальше — запасные.
- **`font-size: 0.88em`** — моноширинные шрифты визуально крупнее обычных при том же размере.
- **`:not(pre) > code`** — только код внутри строки: `` `code` `` получает подложку, а `<code>` внутри блока `<pre>` — нет.
- **`!important` у фона.** `syntax.css` задаёт `.chroma` свой фон (`#f7f7f7` у github, `#0d1117` у github-dark).
  Здесь он заменяется на фон сайта, чтобы код вписывался в палитру.
  **Проверено:** пока `noClasses: false`, `!important` не нужен — `main.css` идёт после `syntax.css` и с той же специфичностью
  побеждает и так: без `!important` фон в светлой теме — `rgb(244, 243, 240)`, в тёмной — `rgb(29, 29, 27)`.
  Он страхует от `noClasses: true`: тогда Chroma пишет фон прямо в `style="…"`, а встроенный стиль перебивается только
  `!important`. **Проверено:** с `noClasses: true` и без `!important` фон блока — `rgb(39, 40, 34)` (monokai) в обеих темах,
  с `!important` — снова фон сайта. Но цвет текста monokai (`#f8f8f2`, почти белый) остаётся — на светлом фоне код
  нечитаем. Так что `noClasses: true` в этом проекте всё равно ломает вид.

### Навигация «раньше / позже»

```css
.pager {
  display: flex;
  justify-content: space-between;
  gap: 1rem;
  margin-top: 3rem;
  padding-top: 1.5rem;
  border-top: 1px solid var(--line);
}
.pager a { max-width: 48%; }
.pager .next { margin-left: auto; text-align: right; }
.pager small { display: block; color: var(--muted); }
```

- **`.pager .next { margin-left: auto; }`** — если у записи нет предыдущей, ссылка «позже» всё равно прижимается вправо:
  автоматический отступ съедает всё свободное место слева. `space-between` для одного элемента прижал бы его влево.
- **`max-width: 48%`** — длинные заголовки переносятся, а не наезжают друг на друга.
- **`small { display: block; }`** — подпись «← раньше» отдельной строкой над заголовком.

## Где ещё пригодится

Набор приёмов из этой главы — переменные с темой в медиазапросе, колонка `max-width` + `margin: auto`, `gap` вместо отступов
у детей, grid для «подпись + значение», `* + *` для разделителей — подходит почти для любого текстового сайта.
Документация, блог, резюме собираются из тех же 200 строк с другими значениями переменных.

## Упражнения

1. Поменяйте `--measure` на `50rem` и `30rem`. Посчитайте символы в строке абзаца. Какая ширина удобнее?
2. Добавьте цвета для `.status-paused`, `.status-finished`, `.status-archived`.
3. В инструментах разработчика (Rendering → Emulate CSS media feature prefers-color-scheme) переключите тему.
   Поставьте в админке ярко-жёлтый акцент и проверьте, читаются ли ссылки в обеих темах.
4. Сделайте, чтобы у внешних ссылок в тексте был значок `↗`: `.content a[href^="http"]::after { content: " ↗"; }`.
   Почему он появится и у ссылок на свой же домен? Как это исправить (подсказка: render-хук ссылок из главы 5)?
5. Разбейте `main.css` на несколько файлов и соберите их через `@import` и `css.Build`.

## Итог

CSS лежит в `assets/`, Hugo Pipes склеивает его, сжимает и добавляет хеш к имени, поэтому файл можно кешировать на год,
а `integrity` защищает от подмены. Все цвета — переменные в `:root`; тёмная тема переопределяет только их, а акцент из админки
приходит отдельным `<style>` и в тёмной теме осветляется через `color-mix`. Раскладка — одна колонка шириной около 60 символов,
flex для шапки и подвала, grid для списков записей, одна точка перестройки на 30rem.

Следующая глава: [`<head>`, поисковики, соцсети, RSS →](07-head-seo-rss.md)
