import { chromium } from 'playwright';
const [,, out] = process.argv;
const base = 'http://localhost:5181';
const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
await ctx.addInitScript(() => localStorage.setItem('ucrm-theme', 'light'));
const page = await ctx.newPage();
const log = (...a) => console.log(...a);
await page.goto(base + '/login', { waitUntil: 'networkidle', timeout: 120000 });
await page.waitForTimeout(1500);
await page.fill('input[type=email]', 'info.socialmediauser1@gmail.com');
await page.fill('input[type=password]', '11223344');
await page.click('button[type=submit]');
await page.waitForURL((u) => !u.pathname.startsWith('/login'), { timeout: 60000 });

// 1. Sample follow-up (browser-only mock) on the converted request
await page.route('**/api/automation/inquiries**', (r) => r.fulfill({ json: {
  can_control: true,
  enrollments: [{ enrollment_id: 'e1', recipe_id: 'r1', recipe_name: 'New request follow-up', version_number: 1,
    subject_type: 'form_submission', state: 'active', source: 'form', current_step_index: 1,
    next_due_at: new Date(Date.now() + 3 * 3600e3).toISOString(), customer_messages_sent: 1,
    stop_reason: null, paused_reason: null, held_reason: null, created_at: new Date().toISOString(), updated_at: new Date().toISOString() }]
}}));
await page.goto(base + '/requests/263f718d-2885-4d91-9b91-919e7e79ffb1');
await page.waitForSelector('.work-header');
await page.hover('#request-follow-up');
await page.waitForSelector('.profit-card');
await page.screenshot({ path: `${out}/followup-mock.png`, clip: { x: 1070, y: 80, width: 370, height: 300 } });
await page.click('.inquiry-automation__control');
await page.waitForTimeout(500);
await page.screenshot({ path: `${out}/followup-menu.png`, clip: { x: 1000, y: 80, width: 440, height: 420 } });
log('menu items:', await page.locator('[role=menuitem]').allInnerTexts());
await page.keyboard.press('Escape');
await page.unroute('**/api/automation/inquiries**');

// 2. Live journey on the test request
await page.goto(base + '/requests/d82d9ea4-343c-4d80-bff4-89d987e528da');
await page.waitForSelector('.work-header');
await page.click('button[aria-label="Edit the service overview"]');
const bar = page.locator('.detail-edit-bar, .sticky-action-bar').first();
await page.waitForTimeout(400);
log('bar visible after pencil:', await bar.isVisible().catch(() => 'n/a'));
const save = page.getByRole('button', { name: /save/i }).last();
log('save disabled before typing:', await save.isDisabled());
await page.fill('#request-description', 'Classic B10a live check text');
log('save disabled after typing:', await save.isDisabled());
await page.screenshot({ path: `${out}/overview-editing.png` });
await page.getByRole('button', { name: /cancel/i }).last().click();
await page.waitForTimeout(400);
log('overview text after cancel:', await page.locator('#request-overview').innerText());

// Tick assessment complete, then untick to restore
const box = page.locator('#assessment-complete');
await box.check();
await page.waitForTimeout(2500);
log('status after tick:', await page.locator('.work-header').innerText().then(t => t.split('\n').slice(0,4).join(' | ')));
await page.screenshot({ path: `${out}/after-complete.png` });
await page.locator('#assessment-complete').uncheck();
await page.waitForTimeout(2500);
log('status after untick:', await page.locator('.work-header').innerText().then(t => t.split('\n').slice(0,4).join(' | ')));

// Open the visit editor via pencil and cancel
await page.click('button[aria-label="Edit the on-site assessment"]');
await page.waitForTimeout(500);
await page.screenshot({ path: `${out}/assessment-editor.png`, fullPage: false });
await page.locator('#request-assessment').getByRole('button', { name: 'Cancel' }).click();
log('editor closed:', await page.locator('.assessment-visit').isVisible());
await browser.close();
