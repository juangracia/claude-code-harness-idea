# Idea: un harness de Claude Code para cualquier repo

Este documento es un "idea file": describe una idea con el detalle justo para que se lo pases a tu agente de código y él la construya en tu repo. No es una librería ni un template para copiar. Es una receta. Tu agente adapta cada pieza a tu stack.

## Índice

1. [Qué es y para qué](#1-qué-es-y-para-qué)
2. [Cómo usarlo](#2-cómo-usarlo)
3. [Orden de construcción](#3-orden-de-construcción)
4. [Los componentes](#4-los-componentes)
   - [4.1 CLAUDE.md corto](#41-claudemd-corto)
   - [4.2 El loop de verify](#42-el-loop-de-verify)
   - [4.3 Scripts del stack local](#43-scripts-del-stack-local)
   - [4.4 Seed de datos](#44-seed-de-datos)
   - [4.5 Agentes con modelo por rol](#45-agentes-con-modelo-por-rol)
   - [4.6 Skills](#46-skills)
   - [4.7 Hooks](#47-hooks)
   - [4.8 La wiki para LLM (segundo cerebro)](#48-la-wiki-para-llm-segundo-cerebro)
   - [4.9 Worktrees en paralelo con base de datos por slot](#49-worktrees-en-paralelo-con-base-de-datos-por-slot)
   - [4.10 Vigilancia de recursos](#410-vigilancia-de-recursos)
   - [4.11 Permisos](#411-permisos)
5. [El proceso: autor + revisor](#5-el-proceso-autor--revisor)
6. [El ciclo de una feature, del plan al PR](#6-el-ciclo-de-una-feature-del-plan-al-pr)
7. [Checklist de "listo"](#7-checklist-de-listo)
8. [Trampas conocidas](#8-trampas-conocidas)
9. [Ejemplo trabajado](#9-ejemplo-trabajado)
10. [Archivos de ejemplo](#10-archivos-de-ejemplo)

---

## 1. Qué es y para qué

Un "harness" es todo lo que rodea al modelo para que trabaje bien en un repo concreto: cómo levanta el stack, cómo sabe si rompió algo, dónde guarda lo que aprende, qué agentes usa para cada tarea y qué cosas tiene prohibidas.

Sin harness, cada sesión arranca de cero. El agente adivina comandos, no sabe si el cambio funciona y olvida lo que descubrió ayer.

Con harness:

- **Un comando dice si todo está bien** (`scripts/verify.sh`). El agente lo corre antes de decir "listo".
- **El conocimiento se acumula** en una wiki dentro del repo, no en el chat.
- **Varias features avanzan en paralelo**, cada una con su propio backend, frontend y base de datos, sin pisarse.
- **Cada paso tiene un autor y un revisor independiente.** El revisor encuentra lo que el autor no ve.
- **Nada llega a `main` sin aprobación humana.**

La idea sirve para cualquier stack. Los ejemplos usan una app real (Spring Boot + React + Postgres), pero cada pieza se describe por lo que hace, no por la tecnología.

## 2. Cómo usarlo

Requisitos de los ejemplos: Claude Code (o tu agente), git con worktrees, Docker, python3, jq, lsof y curl.

1. Copiá este archivo a la raíz de tu repo (o pasale la URL a tu agente).
2. Abrí tu agente de código en el repo y escribí:

   > Leé IDEA.md y armá este harness en mi repo. Primero explorá el repo y levantá el stack. No escribas documentación de algo que no corriste. Mostrame el plan antes de tocar código.

3. Revisá el plan. Pedí cambios. Aprobá.
4. Al final, pedile que corra `scripts/verify.sh` desde un clon limpio y te muestre la salida.

Si tu agente no es Claude Code, las ideas siguen valiendo. Cambian los nombres: hooks, skills y subagentes tienen equivalentes en casi todas las herramientas.

## 3. Orden de construcción

El orden importa. No escribas docs de un stack que no levantaste.

1. **Aislar.** Trabajá en una rama nueva dentro de un git worktree. Nunca en `main`.
2. **Explorar en paralelo.** Cuatro exploradores de solo lectura: backend y arquitectura, frontend, dominio e historia, tests/CI/deploy. El de tests tiene que correr los tests, no solo leerlos.
3. **Levantar el stack local.** Scripts `scripts/dev-*.sh`. Puertos en un `.dev.env` (gitignoreado). Fijá versiones de toolchain (`.nvmrc`, `.sdkmanrc`, `.tool-versions`).
4. **Seed.** Datos realistas usando la API actual.
5. **`scripts/verify.sh`.** Todos los stages, un resumen, exit code distinto de cero si algo falla.
6. **Mirar la app.** Abrirla en un navegador (Playwright o similar). Leer errores de consola.
7. **`CLAUDE.md` corto.**
8. **Wiki.**
9. **Agentes, skills, hooks, permisos.**
10. **Worktrees en paralelo y vigilancia de recursos** (si vas a correr features en paralelo).
11. **Entregar.** Commits chicos. Push de la rama. PR. Nunca push a `main`.

## 4. Los componentes

### 4.1 CLAUDE.md corto

Es el archivo que el agente carga en cada sesión. Si es largo, se ignora. Ponele solo lo que toda sesión necesita:

- Qué es el producto, en una línea.
- Dónde vive cada tipo de conocimiento (ver tabla abajo).
- Comandos: levantar, seed, verify.
- Reglas que no se pueden romper (por ejemplo: "toda query filtra por owner").
- Invariantes de dominio con su `archivo:línea`.
- Definición de "hecho".
- Qué está prohibido sin OK humano (deploy, push a `main`).

Los procedimientos largos van en skills, no acá.

| Dónde | Qué guarda | Quién lo lee |
|---|---|---|
| `CLAUDE.md` (commiteado) | reglas compartidas, cortas | toda sesión |
| `wiki/` (commiteado) | dominio, arquitectura, decisiones, gotchas | el agente antes de explorar código |
| `CLAUDE.local.md` (gitignoreado) | preferencias personales en este repo | solo vos |
| memoria del agente (fuera del repo) | preferencias del usuario | solo vos, nunca hechos del proyecto |

### 4.2 El loop de verify

Un solo comando, `scripts/verify.sh`, que:

- Corre **todos** los stages aunque uno falle (tests backend, lint, build frontend, e2e opcional).
- Imprime un bloque de resumen al final, una línea por stage, `PASS` o `FAIL` con conteos.
- Termina con `verify: OK` o `verify: FAILED` y el exit code correspondiente.
- Acepta `--only <stage>` y `--e2e`.

Dos ideas clave:

- **Baseline de lint.** Si el repo ya tiene errores de lint, no los arregles todos de golpe. Contalos, guardá el número (`LINT_ERROR_BASELINE`) y hacé fallar el stage solo si el número sube. Quien arregla algunos baja el número.
- **Control negativo.** Después de escribir un test, cambiá una expectativa a propósito y confirmá que falla. Después revertí. Un test que nunca falla no prueba nada.

Agregá también un smoke test e2e que compare la UI contra la API (por ejemplo: "el número de contratos activos en el dashboard es igual al que devuelve el endpoint").

Ejemplo: [`examples/scripts/verify.sh`](examples/scripts/verify.sh).

### 4.3 Scripts del stack local

- `scripts/dev-backend.sh`: levanta la base (Docker) y el backend.
- Un `scripts/lib/env.sh` que lee `.dev.env` y deriva puertos, nombre de base y URL de conexión. Todos los scripts lo usan. Así el mismo script sirve para el stack principal y para cada worktree.
- El script elige la versión correcta del toolchain. No confíes en el `JAVA_HOME` o el `node` global.

Ejemplo: [`examples/scripts/lib/env.sh`](examples/scripts/lib/env.sh).

### 4.4 Seed de datos

`scripts/seed.py --reset` (o el lenguaje que uses):

- Usa la API real, no inserts directos, así el seed prueba la API.
- Datos con sabor local (nombres, monedas, documentos del país).
- Cubre los casos que las features necesitan: vencidos, por vencer, sin pagos, con pagos parciales. Si una feature muestra "contratos por vencer" y el seed no tiene ninguno, el test pasa con la lista vacía y no prueba nada.
- Marca como sintético todo dato de referencia inventado (índices, cotizaciones).
- Acepta `--api`, `--db`, `--container` para sembrar un slot específico.

### 4.5 Agentes con modelo por rol

Subagentes en `.claude/agents/*.md`, cada uno con su `model:` fijo en el frontmatter. Regla: **el modelo más barato que alcance**.

| Rol | Modelo sugerido | Qué hace |
|---|---|---|
| Planificador, diseño técnico | el más fuerte (opus) | plan, decisiones, trade-offs |
| Builder backend / frontend | intermedio (sonnet) | código + tests, corre verify de su parte |
| Tester | intermedio (sonnet) | corre e2e contra los puertos del carril, junta evidencia |
| Revisor de código | intermedio u opus según riesgo | revisa el diff, no edita |
| Verifier | chico (haiku) | corre verify y reporta, **no puede editar** (`disallowedTools: Edit, Write`) |
| Curador de la wiki | chico (haiku) | solo edita `wiki/` |

Un hook (ver 4.7) bloquea cualquier llamada a un subagente que no elija modelo a propósito.

Ejemplo: [`examples/.claude/agents/verifier.md`](examples/.claude/agents/verifier.md).

### 4.6 Skills

Una skill es un procedimiento que el agente carga solo cuando lo necesita. Mantienen `CLAUDE.md` corto. Las que valen la pena desde el día uno:

- `dev-stack`: levantar, seed, login local, troubleshooting (puerto ocupado, versión de JDK, cuenta vacía).
- `parallel-worktrees`: crear, levantar, sembrar, verificar y borrar un stack por worktree.
- `wiki-ingest`, `wiki-query`, `wiki-lint`: mantener la wiki.
- `deploy` (si aplica): CLI primero, backup antes, nunca a producción sin OK.

La `description` de cada skill dice **cuándo** usarla, con las frases que un humano diría. Eso es lo que hace que se active.

Ejemplo: [`examples/.claude/skills/parallel-worktrees/SKILL.md`](examples/.claude/skills/parallel-worktrees/SKILL.md).

### 4.7 Hooks

Hooks son comandos que el harness corre en momentos fijos. El modelo no los puede saltear. Tres que dieron resultado:

- **SessionStart**: imprime "leé `wiki/index.md` antes de explorar código" y los últimos 5 eventos de `wiki/log.md`. El agente arranca con contexto.
- **PreToolUse sobre `Agent`**: niega la llamada si no tiene `model` (salvo forks o agentes con `model:` en su frontmatter). Evita que todo corra en el modelo más caro por defecto.
- **Stop que alimenta la wiki**: cuando el agente quiere terminar, el hook mira si hay trabajo fuera de `wiki/` más nuevo que el último `wiki/log.md`. Si lo hay, bloquea **una vez** con el mensaje "si esto dejó un aprendizaje durable, cargalo en la wiki; si no, decí 'no wiki update needed'". Guarda una firma del cambio para no insistir dos veces por el mismo trabajo.

Reglas para todos los hooks: rápidos (timeout de 10 s), **fail open** (si falta `jq` o el input no parsea, permiten y avisan por stderr), y nunca hacen nada destructivo.

Ejemplos: [`examples/.claude/settings.json`](examples/.claude/settings.json), [`examples/.claude/hooks/wiki-ingest-check.sh`](examples/.claude/hooks/wiki-ingest-check.sh).

### 4.8 La wiki para LLM (segundo cerebro)

Sigue el patrón "LLM Wiki" de Andrej Karpathy: https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f

La idea: el conocimiento se escribe una vez y se mantiene al día, en lugar de re-derivarlo en cada pregunta. El LLM escribe la wiki. Los humanos la leen, agregan fuentes y preguntan.

```
wiki/
  AGENTS.md            esquema: reglas para mantener la wiki
  index.md             catálogo de páginas, se lee primero
  log.md               historial append-only
  raw/                 fuentes inmutables (reportes de exploración, docs)
  pages/entities/      una página por entidad de dominio
  pages/concepts/      reglas, flujos, ideas transversales
  pages/architecture/  backend, frontend, deploy, testing, harness
  pages/glossary.md    términos de la UI contra nombres en el código
  pages/decisions.md   decisiones estilo ADR
  pages/open-questions.md  huecos, bugs, dudas
```

Reglas:

- `raw/` no se edita nunca. Es la fuente de verdad.
- Cada afirmación cita `archivo:línea` o una fuente en `raw/`. Lo que no se pudo verificar dice `UNVERIFIED`.
- Cada página tiene frontmatter (`type`, `updated`, `sources`) y al menos un link entrante.
- `log.md` usa encabezados fijos para poder hacer `grep`: `## [AAAA-MM-DD] ingest | título`.
- Tres operaciones: **ingest** (llega una fuente o termina una tarea), **query** (responder desde la wiki, y si la respuesta sirve de nuevo, guardarla como página), **lint** (contradicciones, claims viejos, páginas huérfanas).
- Sin secretos ni datos personales reales.

Detalle de Claude Code: si existe `CLAUDE.md`, `AGENTS.md` no se carga solo. Apuntá a él desde las skills y los agentes.

La carpeta `wiki/` se puede abrir como vault de Obsidian para leerla con grafo y backlinks.

### 4.9 Worktrees en paralelo con base de datos por slot

Para correr varias features a la vez, cada una vive en su propio git worktree con su propio stack completo. Un script (`scripts/wt.sh`) lo maneja:

```
scripts/wt.sh new <nombre> [base]   crea worktree + rama + slot libre
scripts/wt.sh up <nombre>           levanta base, backend y frontend del slot
scripts/wt.sh seed <nombre>         resetea y siembra solo la base de ese slot
scripts/wt.sh verify <nombre> --e2e corre verify contra los puertos del slot
scripts/wt.sh ls                    slots, puertos, estado, memoria por stack
scripts/wt.sh down <nombre>
scripts/wt.sh rm <nombre>           baja todo, borra contenedor y volumen, deja la rama
```

| Slot | Backend | Frontend | Base de datos |
|---|---|---|---|
| 0 (principal) | 8080 | 3000 | contenedor principal |
| N (1..4) | 8080+N | 3000+N | contenedor propio en 5440+N, volumen propio |

Puntos que importan:

- **Un contenedor de base por slot**, con su propio volumen. Las bases nunca se mezclan. Una base compartida con esquemas distintos parece funcionar hasta que dos ramas cambian el esquema.
- El slot se escribe en el `.dev.env` del worktree. Todos los scripts lo leen, así `verify.sh` dentro del worktree apunta a sus propios puertos.
- **Límites**: `MAX_STACKS` (por defecto 4) y `MIN_FREE_MEM_PCT` (por defecto 15). `up` se niega si se pasan. `--force` para saltear.
- **Stacks livianos**: JVM con heap chico y un solo hilo de GC, base con buffers chicos y tope de memoria del contenedor, pool de conexiones chico.
- El frontend usa puerto estricto: si está ocupado, falla. Mejor fallar que caer en silencio en el puerto de otro slot.
- `rm` se niega si hay cambios sin commitear.

El ejemplo está pensado para macOS (`memory_pressure`, `footprint`, `stat -f`). En Linux, tu agente tiene que portar el chequeo de memoria (por ejemplo `MemAvailable` de `/proc/meminfo`) y usar `stat -c`.

Ejemplo recortado: [`examples/scripts/wt.sh`](examples/scripts/wt.sh).

### 4.10 Vigilancia de recursos

Con 3 o 4 stacks más varias sesiones de agente, la máquina se queda sin memoria. Un script (`scripts/resource-watch.sh`) corre en segundo plano y emite **una línea solo cuando cambia el estado** (`OK`, `WARN`, `CRIT`): memoria libre, swap, carga, cuántos stacks, cuánta memoria usa cada uno.

- Corrélo bajo un monitor del agente, así el coordinador se entera de un `CRIT` sin mirar.
- Guardá muestras en un CSV y agregá `--report`: te dice cuántos stacks en paralelo aguantó tu máquina sin bajar del umbral.
- En macOS, `ps` RSS subestima mucho la memoria de una JVM (por compresión de memoria). Usá `footprint` o `top`.

### 4.11 Permisos

En `.claude/settings.json`:

- **allow**: los comandos seguros y frecuentes (verify, seed, tests, lint, build, curl a localhost). Menos prompts.
- **deny**: lo destructivo o irreversible (borrar servicios de deploy, push a `main`/`master`).

## 5. El proceso: autor + revisor

Esta es la parte que más cambió la calidad del resultado.

**Un coordinador que solo rutea.** Una sesión principal no escribe código. Reparte trabajo, junta conclusiones (no volcados de archivos) y le pregunta al humano lo que solo el humano decide.

**Cada paso tiene dos workers:**

- Un **autor** que hace el trabajo (plan, diseño, código, tests, PR).
- Un **revisor independiente** que lo revisa con contexto propio, sin haber escrito nada.

**Debaten directo entre ellos**, sin pasar por el coordinador. Máximo **2 rondas**. El revisor dice "agreed" o lista hallazgos concretos con evidencia (`archivo:línea`, un comando corrido). El autor arregla o rebate con razones. Si después de 2 rondas no hay acuerdo, sube al coordinador y de ahí al humano.

**Modelo suficiente por rol.** El plan y el diseño técnico con el modelo más fuerte. Build y tests con el intermedio. Chequeos mecánicos (correr verify, lint de la wiki) con el chico.

**Evidencia, no promesas.** "Lo arreglé" no cuenta. Cuenta el diff, la salida del comando, el screenshot.

## 6. El ciclo de una feature, del plan al PR

```
requisito
  -> plan                     (autor opus + revisor)          -> OK humano
  -> diseño técnico           (autor + revisor)
  -> plan de tests            (autor + revisor)
  -> carriles en paralelo, uno por feature, cada uno en su worktree/slot:
       build                  (builder + revisor de código)
       tests                  (tester + revisor de tests, contra los puertos del carril)
       PR                     (autor + revisor del PR)
  -> humano revisa y mergea
```

**Plan.** Qué se hace y qué no, flujo de usuario, datos, backend, frontend, i18n, tests, definición de hecho por feature. Lista explícita de "decisiones para el humano". Cruces entre features (archivos que tocan las dos, migraciones). Riesgos. Tamaño por paso.

**Diseño técnico.** Endpoints, entidades, queries, componentes. Cómo se respeta cada invariante del `CLAUDE.md`.

**Plan de tests.** Cuatro partes:

1. Tests de backend (unitarios e integración, incluyendo los casos negativos y de permisos).
2. Tests de UI (e2e contra el stack del carril).
3. Conformidad con el mockup, si hay diseño: qué pantalla, qué elementos, qué textos.
4. **Tabla de diferencias deliberadas**: donde la implementación se aparta del mockup a propósito, con el motivo. Así el revisor no lo marca como bug y el humano lo ve.

**Carriles.** Un worktree y un slot por feature (`scripts/wt.sh new req-001`). Cada carril tiene builder, revisor, tester y revisor de tests propios.

**Revisión de código por carril.** El revisor lee el diff contra el plan, el diseño y las reglas del `CLAUDE.md`.

**Test por carril.** El tester corre backend y UI **contra los puertos de ese carril**, con evidencia: salida de `verify.sh`, screenshots, el SHA probado.

**PR por carril.** Descripción con qué cambia, cómo se probó, el SHA, la tabla de diferencias deliberadas. **Nunca se mergea sin aprobación humana.**

## 7. Checklist de "listo"

Una tarea está lista cuando:

- [ ] El comportamiento nuevo tiene un test que **falla sin el cambio** (control negativo hecho).
- [ ] `scripts/verify.sh --e2e` termina en `verify: OK` en el SHA final.
- [ ] Alguien miró el flujo en la UI real, con screenshot y consola sin errores.
- [ ] Los tests corren con datos que ejercitan el caso (no una lista vacía).
- [ ] El revisor dijo "agreed" sobre el **último** commit, no sobre uno anterior.
- [ ] Si `HEAD` se movió después del test, se volvió a testear.
- [ ] Lo aprendido está en `wiki/` con una entrada en `log.md`.
- [ ] El PR existe, CI está verde en el último SHA, y espera aprobación humana.

Y para el harness en sí:

- [ ] Un clon limpio puede seguir el `CLAUDE.md` y llegar a `verify: OK`.
- [ ] El control negativo de verify falló cuando debía.
- [ ] Los formatos (skills, agentes, hooks) se chequearon contra la documentación oficial de tu herramienta.

## 8. Trampas conocidas

Todas pasaron de verdad.

- **El glob que no matchea.** Un `verify.sh` buscaba specs e2e con un glob relativo a otro directorio. No encontraba ninguna y el stage pasaba. Lo encontró un builder. Usá rutas absolutas, `shopt -s nullglob`, e imprimí cuántos archivos corriste.
- **Tests que pasan con datos vacíos.** Un test de "contratos por vencer" pasaba porque la lista estaba vacía. Solución: el seed incluye cada caso que una feature muestra, y el test verifica que hay al menos un elemento antes de comparar.
- **"Lo arreglé" pero el archivo no cambió.** Un autor reportó un fix que nunca se escribió. El revisor lo encontró mirando el diff. El revisor siempre lee el diff, no el reporte.
- **Test viejo después de que se movió HEAD.** Un carril pasó los tests, después entró otro commit. El "verde" ya no valía. Siempre anotá el SHA probado y volvé a testear si cambió.
- **Bases compartidas entre worktrees.** Dos ramas cambiando el esquema en la misma base se rompen entre sí. Un contenedor por slot.
- **Puertos que se corren solos.** Un dev server que salta al siguiente puerto libre termina sirviendo en el puerto de otro slot. Puerto estricto.
- **Variables de entorno que se filtran.** Un `PORT` o `DATABASE_URL` del shell del coordinador pisa los del slot. Al correr algo en un slot, limpiá esas variables y cargá las del slot.
- **Versión del toolchain.** El `JAVA_HOME` global era una versión que rompe una librería del proyecto. El script elige la versión correcta.
- **Medir memoria mal.** En macOS `ps` muestra una JVM viva con 17 MB. Usá `footprint`.
- **Perfiles que abren todo.** Un perfil de desarrollo sin auth hace que los tests de 401/403 pasen o fallen por la razón equivocada. Los tests de permisos no usan ese perfil.
- **`AGENTS.md` invisible.** Con `CLAUDE.md` presente, Claude Code no carga `AGENTS.md` solo. Referencialo explícitamente.
- **Gitignore global.** Algunos usuarios tienen `CLAUDE.md` o `.claude/` en su gitignore global. Commitealos con `git add -f`.
- **Stacked PRs y CI.** Un PR cuya base es otra rama de feature puede no disparar CI. Cambiar la base no lo vuelve a disparar; cerrar y reabrir sí.

## 9. Ejemplo trabajado

La idea se armó sobre una app de gestión de alquileres:

- Backend Spring Boot 3 (Java 17, Maven), Postgres en Docker.
- Frontend React 19 + Vite + MUI.
- Invariante principal: cada registro tiene un dueño y toda query filtra por él.

En un día:

1. Repo frío a harness completo: stack local, seed, `verify.sh` con baseline de lint y smoke e2e, `CLAUDE.md`, wiki con 5 reportes de exploración ingeridos, 4 agentes, 6 skills, 3 hooks.
2. Dos features (morosidad y alertas de vencimiento) planeadas, diseñadas y con plan de tests, cada paso con autor + revisor.
3. Dos carriles en paralelo, cada uno en su worktree con su backend (`:8081`, `:8082`), frontend (`:3001`, `:3002`) y Postgres propios, con el vigilante de recursos corriendo.
4. Un PR por carril, esperando aprobación humana.

Para tu stack, reemplazá: Maven por tu build, Postgres por tu base, Vite por tu dev server, Playwright por tu herramienta e2e. La estructura queda igual.

## 10. Archivos de ejemplo

En [`examples/`](examples/) hay versiones recortadas y genéricas. Son referencia, no para copiar tal cual. Tu agente los adapta.

| Archivo | Qué muestra |
|---|---|
| [`examples/scripts/verify.sh`](examples/scripts/verify.sh) | stages, resumen, baseline de lint, glob seguro para e2e |
| [`examples/scripts/lib/env.sh`](examples/scripts/lib/env.sh) | puertos y base derivados de `.dev.env` |
| [`examples/scripts/wt.sh`](examples/scripts/wt.sh) | slots, contenedor por slot, límites de stacks y memoria |
| [`examples/.claude/settings.json`](examples/.claude/settings.json) | permisos y los tres hooks |
| [`examples/.claude/hooks/session-start.sh`](examples/.claude/hooks/session-start.sh) | apunta a la wiki al arrancar cada sesión |
| [`examples/.claude/hooks/require-agent-model.sh`](examples/.claude/hooks/require-agent-model.sh) | obliga a elegir modelo en cada subagente |
| [`examples/.claude/hooks/wiki-ingest-check.sh`](examples/.claude/hooks/wiki-ingest-check.sh) | Stop hook que alimenta la wiki |
| [`examples/.claude/agents/verifier.md`](examples/.claude/agents/verifier.md) | agente que verifica y no puede editar |
| [`examples/.claude/skills/parallel-worktrees/SKILL.md`](examples/.claude/skills/parallel-worktrees/SKILL.md) | skill con descripción que dispara bien |
| [`examples/wiki/AGENTS.md`](examples/wiki/AGENTS.md) | esquema de la wiki |

No hay ejemplo de `scripts/dev-backend.sh`, `scripts/seed.py`, `scripts/resource-watch.sh` ni de las skills `dev-stack` y `wiki-*`. Dependen demasiado de cada stack. Tu agente los escribe a partir de las secciones 4.3, 4.4, 4.6 y 4.10.
