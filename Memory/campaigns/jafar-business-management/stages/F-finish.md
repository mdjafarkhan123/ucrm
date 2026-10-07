# Jafar Business Management — stage F: Final tour

| Part | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| F1 Final desktop and phone tour | Jafar tours every screen as himself and each role; found problems fixed; speed rechecked on phone | All other parts | Jafar approves release one in the browser | Not started |

Playwright reads `.env` raw, so the owner password hash keeps its `\$` escapes and owner sign-in fails; pass `SUPER_ADMIN_PASSWORD_HASH` unescaped when running `/jafar` browser tests (D2's `src/routes/jafar/team-access.e2e.ts` also needs `JAFAR_TEST_TEAMMATE_EMAIL`/`_PASSWORD`).
