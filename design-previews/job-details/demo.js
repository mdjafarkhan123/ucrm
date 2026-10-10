// Standalone approval demo. All changes are held in this tab; no network writes.
const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];
const dialog = $('#preview');
dialog.classList.add('demo-dialog');
let scenario = 'populated';
let staged = new Map();
let storedTitle = 'Backyard transformation';
let storedInstructions = $('.instructions > p').textContent.trim();
let lastFocus;
let selectedVisit;

let toastTimer;
const esc = (value) =>
	String(value).replace(
		/[&<>"']/g,
		(c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]
	);
const button = (label, action, primary = false) =>
	`<button class="button ${primary ? 'button--primary' : ''}" data-action="${action}">${label}</button>`;
const field = (label, value = '', type = 'text') =>
	`<label>${label}<input type="${type}" value="${esc(value)}"></label>`;
const select = (label, options) =>
	`<label>${label}<select>${options.map((o) => `<option>${o}</option>`).join('')}</select></label>`;
const area = (label, value = '') =>
	`<label>${label}<textarea rows="4">${esc(value)}</textarea></label>`;
const check = (label, checked = false) =>
	`<label><input type="checkbox" ${checked ? 'checked' : ''}> ${label}</label>`;
function notify(text) {
	$('#feedback').textContent = text;
	clearTimeout(toastTimer);
	toastTimer = setTimeout(() => ($('#feedback').textContent = ''), 4500);
}
function open(title, body, actions = '') {
	lastFocus = document.activeElement;
	$('#preview-title').textContent = title;
	$('#preview-body').innerHTML = body;
	$('#preview-actions').innerHTML = button('Cancel', 'close') + actions;
	if (!dialog.open) dialog.showModal();
}
function close() {
	dialog.close();
}
dialog.addEventListener('close', () => lastFocus?.focus());
dialog.addEventListener('click', (e) => {
	if (e.target === dialog) {
		const r = dialog.getBoundingClientRect();
		if (e.clientX < r.left || e.clientX > r.right || e.clientY < r.top || e.clientY > r.bottom)
			close();
	}
});
function draft() {
	$('.edit-bar').hidden = false;
	document.body.classList.add('is-editing');
	$('#draft-state').textContent = staged.size ? 'Unsaved changes · preview only' : 'No changes yet';
	$('#save-draft').disabled = !staged.size;
}
function stage(id, value, apply) {
	staged.set(id, { value, apply });
	draft();
	close();
	notify('Change staged. Use Save changes to keep it in this preview.');
}
function discard() {
	staged.clear();
	$('#title-editor').hidden = true;
	$('#job-title').hidden = false;
	$('#title-draft').value = storedTitle;
	$('.edit-bar').hidden = true;
	document.body.classList.remove('is-editing');
}
function saveDraft() {
	if (!staged.size) return;
	staged.forEach((x) => x.apply?.(x.value));
	discard();
	notify('Simulated save complete. Reload resets the sample data.');
}
$('#discard').onclick = discard;
$('#save-draft').onclick = saveDraft;
$('#title-draft').addEventListener('input', (e) => {
	const v = e.target.value.trim();
	if (v && v !== storedTitle)
		staged.set('title', {
			value: v,
			apply: (value) => {
				storedTitle = value;
				$('#job-title').textContent = value;
			}
		});
	else staged.delete('title');
	draft();
});
function editTitle() {
	$('#title-editor').hidden = false;
	$('#job-title').hidden = true;
	$('#title-draft').value = storedTitle;
	draft();
	$('#title-draft').focus();
}
const editor = (title, body, callback, label = 'Save preview') => {
	open(
		title,
		body +
			'<label class="preview-outcome">Demo save outcome<select id="preview-outcome"><option value="success">Success</option><option value="error">Error · keep my changes</option></select></label><p id="preview-error" role="alert" hidden></p>',
		button(label, 'submit', true)
	);
	$('#preview-actions [data-action=submit]').onclick = () => {
		if ($('#preview-outcome').value === 'error') {
			$('#preview-error').hidden = false;
			$('#preview-error').textContent =
				'Those changes could not be saved. Your draft is still here. Choose Success to retry this preview.';
			return;
		}
		callback();
	};
};
const saveLocal = (message = 'Simulated save complete. Reload resets this preview.') => {
	close();
	notify(message);
};
function confirm(title, copy, callback, label = 'Confirm preview') {
	editor(title, `<p>${copy}</p>`, callback, label);
}
function menu(title, items) {
	open(
		title,
		`<div class="menu-list">${items.map(([label, action]) => button(label, action)).join('')}</div>`
	);
}
function visitMenu() {
	const done = selectedVisit?.classList.contains('visit--complete');
	const items = [['Notes, photos and files', 'visit-records']];
	if (scenario !== 'closed')
		items.push([
			done ? 'Mark incomplete' : 'Mark complete',
			done ? 'incomplete-visit' : 'complete-visit'
		]);
	if (!['restricted', 'closed'].includes(scenario) && !done)
		items.push(
			['Edit this visit', 'edit-visit'],
			['Duplicate visit', 'duplicate-visit'],
			['Delete visit', 'delete-visit']
		);
	if (['recurring', 'period'].includes(scenario) && !done)
		items.push(['Apply time and crew to later visits', 'future-visits']);
	menu((selectedVisit?.querySelector('h3')?.textContent || 'Visit') + ' · actions', items);
}
function renderReport() {
	return (
		'<article class="report-document"><p class="eyebrow">OAK & STONE · WORK REPORT</p><h2>' +
		esc(storedTitle) +
		'</h2><p>Prepared for Emma Wilson · 1248 Willow Creek Drive</p><p>Site prepared and old materials removed. Patio installation is scheduled for October 12.</p><h3>Work completed</h3><p>Site preparation · Oct 9 · Marcus Reed & Alex Lee</p><img src="./assets/site-progress.svg" alt="Illustrated progress photo"><h3>Customer sign-off</h3><p>Emma Wilson · Work authorization · Oct 7</p><p>Selected checklist answers: Site access confirmed. Existing damage recorded.</p></article>'
	);
}
function setNavigation(open) {
	document.body.classList.toggle('nav-open', open);
	$('.mobile-menu').setAttribute('aria-expanded', String(open));
	$('.app').inert = open;
	if (open) $('#navigation a').focus();
	else $('.mobile-menu').focus();
}
const actions = {
	close,
	navigation: () => setNavigation(!document.body.classList.contains('nav-open')),
	'edit-job': editTitle,
	history: () => open('Job history', $('#activity .activity').innerHTML),
	more: () =>
		menu('Job actions', [
			['Preview work report', 'report'],
			['Print work report', 'print-report'],
			['Copy work report link', 'copy-report']
		]),
	invoice: () =>
		open(
			'Create invoice · destination preview',
			'<p>The real app opens the invoice builder with this job’s billable work selected.</p><div class="detail-row"><strong>' +
				esc(storedTitle) +
				'</strong><span>' +
				(scenario === 'recurring'
					? '$120.00 per selected visit'
					: scenario === 'period'
						? '$500.00 for September'
						: '$8,715.00 remaining stage') +
				'</span></div><p>No invoice is created or sent from this demo.</p>'
		),
	'invoice-link': () =>
		open(
			'Invoice #302 · destination preview',
			'<p>Deposit · $3,735.00 · Invoiced</p><p>The real app opens the existing invoice here.</p>'
		),
	hours: () =>
		editor(
			'Add time entry',
			select(
				'Whose hours',
				scenario === 'restricted' ? ['Marcus Reed (you)'] : ['Marcus Reed', 'Alex Lee']
			) +
				field('Work date', '2026-10-09', 'date') +
				field('Hours', '8', 'number') +
				field('Minutes', '0', 'number') +
				select('Visit', ['Site preparation · Oct 9', 'Not tied to a visit']) +
				area('Notes'),
			() => {
				const n = $('#preview-body input[type=number]').value;
				$('#labor .subtle').textContent = `${16 + Number(n)} hours recorded · Sample entry added`;
				saveLocal();
			}
		),
	'edit-hours': () =>
		editor(
			'Edit hours',
			field('Hours', '8', 'number') +
				field('Minutes', '0', 'number') +
				area('Notes', 'Site preparation'),
			() => saveLocal()
		),
	'remove-hours': () =>
		confirm(
			'Remove these hours?',
			'Remove Marcus Reed’s 8-hour entry? The real app keeps an audit trail.',
			() => {
				$('#labor .detail-row').remove();
				saveLocal('Sample hours removed.');
			},
			'Remove hours'
		),
	expense: () =>
		editor(
			'Expense',
			field('Description', 'Disposal fee') +
				field('Amount', '120.00', 'number') +
				field('Date', '2026-10-09', 'date') +
				select('Reimburse', ['Not reimbursable', 'Marcus Reed', 'Alex Lee']) +
				field('Receipt (sample file)', '', 'file'),
			() => saveLocal()
		),
	'remove-expense': () =>
		confirm(
			'Remove this expense?',
			'Remove the $120.00 disposal fee from this job?',
			() => {
				$('#expenses .detail-row').remove();
				saveLocal();
			},
			'Remove expense'
		),
	receipt: () =>
		open(
			'Receipt · sample',
			'<p>Disposal fee · October 9, 2026</p><p>Amount paid: $120.00</p><p>Illustrative receipt preview.</p>'
		),
	checklist: () =>
		editor(
			'Add checklist',
			select('Checklist template', ['Site safety & handover', 'Installation quality check']) +
				'<p>Every visit receives its own questions. Previously completed visits are preserved.</p>',
			() => {
				$('#checklists .panel__body').insertAdjacentHTML(
					'beforeend',
					'<p>Installation quality check · 4 questions · Added in preview</p>'
				);
				saveLocal();
			},
			'Attach checklist'
		),
	'remove-checklist': () =>
		confirm(
			'Remove this checklist?',
			'This removes the checklist and its 2 saved answers from this job’s visits.',
			() => {
				$('#checklists .detail-row').remove();
				saveLocal();
			},
			'Remove checklist'
		),
	'add-visit': () =>
		menu('Add visits', [
			['Add one visit', 'single-visit'],
			['Add multiple visits', 'multiple-visits']
		]),
	'single-visit': () => visitEditor(false),
	'multiple-visits': () => visitEditor(true),
	'edit-visit': () => visitEditor(false, true),
	'visit-menu': visitMenu,
	'duplicate-visit': () =>
		confirm(
			'Duplicate visit',
			'Copy this visit’s schedule, crew and instructions into a new unfinished visit?',
			() => {
				const row = (selectedVisit || $('#visits .visit')).cloneNode(true);
				row.querySelector('h3').textContent += ' · Copy';
				$('#visits').append(row);
				saveLocal('Sample visit duplicated.');
			},
			'Duplicate preview'
		),
	'delete-visit': () =>
		confirm(
			'Delete this visit?',
			'Only this unfinished visit will be removed. Completed visits are protected.',
			() => {
				(selectedVisit || $('#visits .visit:not(.visit--complete)'))?.remove();
				saveLocal();
			},
			'Delete visit'
		),
	'complete-visit': () =>
		confirm(
			'Required checklist answers are blank',
			'One required answer remains. You may return to the checklist or complete this visit anyway.',
			() => {
				selectedVisit?.classList.add('visit--complete');
				if (selectedVisit?.querySelector('.badge'))
					selectedVisit.querySelector('.badge').textContent = 'Completed';
				const final = $$('#visits .visit:not(.visit--complete)').length === 0;
				if (final && scenario !== 'restricted' && !['recurring', 'period'].includes(scenario))
					menu('Final visit completed', [
						['Finish job', 'finish-job'],
						['Add a return visit', 'single-visit'],
						['Keep job open', 'keep-open']
					]);
				else if (scenario === 'recurring')
					menu('Visit completed', [
						['Invoice now', 'invoice'],
						['Invoice later', 'invoice-later']
					]);
				else saveLocal('Visit completed in preview.');
			},
			'Complete anyway'
		),
	'incomplete-visit': () =>
		confirm(
			'Mark visit incomplete?',
			'This visit returns to unfinished work. Issued invoice pricing stays fixed.',
			() => {
				selectedVisit?.classList.remove('visit--complete');
				saveLocal();
			}
		),
	'keep-open': () =>
		menu('Visit completed', [
			['Invoice now', 'invoice'],
			['Invoice later', 'invoice-later']
		]),
	'invoice-later': () =>
		saveLocal('Sample visit completed. Invoice reminder stays with your team.'),
	'finish-job': () =>
		confirm(
			'Finish job?',
			'Upcoming unfinished visits will be removed. Completed visits and their records stay on the job.',
			() => {
				close();
				$('#scenario').value = 'closed';
				applyScenario('closed');
				notify('Job closed in this preview only.');
			},
			'Finish job preview'
		),
	reopen: () =>
		confirm(
			'Reopen job?',
			'The job becomes active again. Removed visits are not recreated; add visits separately.',
			() => {
				close();
				$('#scenario').value = 'populated';
				applyScenario('populated');
				notify('Job reopened in this preview.');
			},
			'Reopen preview'
		),
	'future-visits': () =>
		editor(
			'Apply to later visits',
			check('Copy time of day', true) +
				check('Copy assigned team', true) +
				'<p>Applies to 2 later unfinished visits. Dates and completed visits stay unchanged.</p>',
			() => saveLocal(),
			'Apply preview'
		),
	recurrence: () =>
		editor(
			'Edit all unfinished visits',
			select('Repeat', ['Weekly on Mondays', 'Every 2 weeks', 'Monthly', 'Custom']) +
				field('End date', '2026-12-28', 'date') +
				'<p>2 incomplete visits will be removed and recreated. Their custom details will be lost. Completed visits remain.</p>' +
				check('I understand the incomplete visits will be replaced'),
			() => {
				if (!$('#preview-body input[type=checkbox]').checked) {
					notify('Please acknowledge the schedule change first.');
					return;
				}
				saveLocal();
			},
			'Replace visits preview'
		),
	'visit-records': () =>
		editor(
			'Visit records · Patio installation',
			'<p>Notes, photos, files and checklist answers belong to this visit.</p>' +
				area('Visit note', 'Gate access confirmed.') +
				'<h3>Site safety & handover</h3>' +
				check('Site access confirmed', true) +
				check('Work area made safe') +
				field('Surface measurement', '32', 'number') +
				area('Handover notes') +
				'<h3>Photos and files</h3><img src="./assets/site-before.svg" alt="Illustrated visit photo">' +
				field('Add sample file', '', 'file'),
			() => saveLocal('Visit records saved in preview memory.')
		),
	instructions: () =>
		editor(
			'Crew instructions',
			area('Notes for the crew', storedInstructions),
			() => {
				const v = $('#preview-body textarea').value;
				stage('instructions', v, (value) => {
					storedInstructions = value;
					$('.instructions > p').textContent = value;
				});
			},
			'Stage instructions'
		),
	scope: () =>
		editor(
			'Products and services',
			'<p>Changes apply to this job only.</p>' +
				field('Product or service', 'Natural stone patio') +
				area('Description', 'Premium sandstone · supply & installation') +
				field('Quantity', '1', 'number') +
				field('Unit price', '8500', 'number') +
				field('Internal unit cost', '3200', 'number') +
				check('Taxable', true) +
				button('Add line', 'add-line') +
				'<div id="extra-lines"></div>',
			() => {
				if ($('#signatures .badge')) $('#signatures .badge').textContent = 'Job changed';
				saveLocal('Scope saved in this preview only. The previous signature stays unchanged.');
			},
			'Save scope preview'
		),
	'add-line': () =>
		$('#extra-lines').insertAdjacentHTML(
			'beforeend',
			field('New product or service') +
				field('Quantity', '1', 'number') +
				field('Unit price', '0', 'number')
		),
	note: () =>
		editor(
			'Job note',
			area('Note', 'Emma will leave the side gate unlocked. Keep it closed while working.'),
			() => {
				const v = $('#preview-body textarea').value;
				stage('note', v, (value) => ($('#notes .panel__body > p').textContent = value));
			},
			'Stage note'
		),
	'pin-note': () =>
		stage('pin', true, () => ($('#notes .detail-row strong').textContent = 'Gate access')),
	'delete-note': () =>
		confirm(
			'Delete this note?',
			'This change waits for the job’s Save changes button.',
			() =>
				stage(
					'delete-note',
					true,
					() => ($('#notes .panel__body').innerHTML = '<p>No notes yet.</p>')
				),
			'Stage deletion'
		),
	files: () =>
		editor(
			'Add files',
			select('Choose from', ['Upload sample files', 'Existing client files']) +
				field('Choose files', '', 'file') +
				field('Caption', 'Site progress') +
				field('Labels', 'Patio, progress'),
			() =>
				stage('files', true, () =>
					$('#files .panel__body').insertAdjacentHTML(
						'beforeend',
						'<p>Sample file attached in preview.</p>'
					)
				),
			'Stage files'
		),
	'file-labels': () =>
		editor(
			'File caption and labels',
			field('Caption', 'Materials list') +
				field('Labels', 'Landscape') +
				button('Remove from this job', 'remove-file'),
			() => stage('file-labels', true),
			'Stage changes'
		),
	'remove-file': () =>
		confirm(
			'Remove file from this job?',
			'The file remains in the shared Files library.',
			() => stage('remove-file', true, () => $('#files .detail-row:last-of-type')?.remove()),
			'Stage removal'
		),
	photo: () =>
		open(
			'Job photos · 1 of 2',
			'<img id="lightbox-photo" src="./assets/site-before.svg" alt="Illustrated backyard before work"><p id="photo-counter">Before · backyard · 1 of 2</p>',
			button('Previous', 'previous-photo') +
				button('Next', 'next-photo') +
				button('Download preview', 'download-file')
		),
	'next-photo': () => {
		$('#lightbox-photo').src = './assets/site-progress.svg';
		$('#lightbox-photo').alt = 'Illustrated patio progress';
		$('#photo-counter').textContent = 'Patio · progress · 2 of 2';
	},
	'previous-photo': () => {
		$('#lightbox-photo').src = './assets/site-before.svg';
		$('#lightbox-photo').alt = 'Illustrated backyard before work';
		$('#photo-counter').textContent = 'Before · backyard · 1 of 2';
	},
	file: () =>
		open(
			'Landscape plan.pdf · preview',
			'<h3>Oak & Stone · Landscape plan</h3><p>32 m² sandstone patio, native planting beds, and side-gate access.</p><p>Sample document · 240 KB</p>',
			button('Download preview', 'download-file')
		),
	'download-file': () => notify('Download preview: no real file is downloaded.'),
	signature: () =>
		editor(
			'Collect signature',
			select('Signature type', ['Work authorization', 'Work completion', 'Other']) +
				select('Visit', ['Not tied to a visit', 'Patio installation · Oct 12']) +
				field('Signer name', 'Emma Wilson') +
				'<p>I authorize the work described in this job.</p><label>Signature (type for preview)<input placeholder="Emma Wilson" required></label>' +
				check('The signer agrees to this statement'),
			() => {
				if (!$('#preview-body input[type=checkbox]').checked) {
					notify('Confirm the sample statement first.');
					return;
				}
				$('#signatures .panel__body').insertAdjacentHTML(
					'beforeend',
					'<p>Emma Wilson · Additional sample signature · Current</p>'
				);
				saveLocal('Sample signature collected. No document was signed.');
			},
			'Collect preview'
		),
	'signature-snapshot': () =>
		open(
			'Signed job snapshot',
			'<p>Emma Wilson · Work authorization · Oct 7, 2026</p><p>I authorize the work described in this job.</p><p>Natural stone patio, landscape planting, and site preparation.</p><p>Frozen job snapshot · Customer prices appear only for members allowed to see them.</p><p>This frozen copy stays unchanged. Later changes show a stale signature beside a new one.</p>'
		),
	'edit-report': () =>
		editor(
			'Edit work report',
			check('Show work list', true) +
				check('Show prices', true) +
				select('Signature', ['Emma Wilson · Oct 7', 'No signature']) +
				area('Summary for the customer', 'Site prepared and old materials removed.') +
				'<h3>Include photos</h3>' +
				check('Before · backyard', true) +
				check('Patio · progress', true) +
				button('Photo layout', 'report-layout') +
				'<h3>Checklist answers</h3>' +
				check('Site access confirmed', true),
			() => saveLocal('Work report saved in preview only.')
		),
	'report-layout': () =>
		editor(
			'Work report photo layout',
			select('Layout', ['Single photo', 'Before / after pair']) +
				field('Section heading', 'Patio progress') +
				button('Move photo earlier', 'layout-up') +
				button('Move photo later', 'layout-down'),
			() => saveLocal('Sample photo layout saved.')
		),
	'layout-up': () => notify('Sample photo moved earlier.'),
	'layout-down': () => notify('Sample photo moved later.'),
	report: () => open('Customer work report · preview', renderReport()),
	'print-report': () =>
		open(
			'Print work report · preview',
			renderReport() + '<p>In the real app, this opens the browser’s print dialog.</p>'
		),
	'copy-report': () =>
		open(
			'Work report link · preview',
			'<p>A customer-safe read-only link would be copied in the real app.</p><code>https://example.com/report/sample</code><p>No real link is generated or shared.</p>'
		),
	billing: () =>
		editor(
			'Billing setup',
			select(
				'How is this work priced?',
				scenario === 'recurring' || scenario === 'period'
					? ['Per completed visit', 'Fixed per billing period']
					: ['Job total']
			) +
				select('Remind our team to invoice', [
					'When the job closes',
					'After every visit',
					'At month end',
					'On custom dates',
					'Manually · no reminders'
				]) +
				'<p>Payment collection stays separate. Nothing here charges the client.</p>',
			() => {
				$('#billing-timing').textContent = $$('#preview-body select')[1].value;
				saveLocal();
			},
			'Save billing preview'
		),
	stages: () =>
		editor(
			'Payment schedule',
			'<p>Invoiced stages are locked. Remaining stages must add up to the job total.</p>' +
				'<label>Deposit · invoiced, locked<input value="$3,735.00" disabled></label>' +
				field('Remaining stage name', 'Completion') +
				field('Remaining amount', '8715.00', 'number'),
			() => {
				if (Number($('#preview-body input[type=number]').value) !== 8715) {
					notify('Remaining stages must total $8,715.00.');
					return;
				}
				saveLocal();
			},
			'Save schedule preview'
		),
	reminder: () =>
		editor(
			'Add invoice reminder',
			field('Remind our team on', '2026-10-14', 'date'),
			() => {
				$('#reminders .panel__body').insertAdjacentHTML(
					'beforeend',
					'<p>Additional sample reminder added.</p>'
				);
				saveLocal();
			},
			'Save reminder preview'
		),
	'reminder-done': () =>
		confirm(
			'Mark reminder as invoiced?',
			'This clears the internal reminder; it does not create or send an invoice.',
			() => {
				$('#reminders .detail-row').remove();
				saveLocal();
			}
		),
	'remove-reminder': () =>
		confirm(
			'Delete invoice reminder?',
			'This removes the prompt for your team.',
			() => {
				$('#reminders .detail-row').remove();
				saveLocal();
			},
			'Delete preview'
		),
	discount: () =>
		editor(
			'Job discount',
			field('Discount name', 'Courtesy discount') +
				select('Type', ['Percentage', 'Fixed amount']) +
				field('Value', '0', 'number'),
			() => saveLocal()
		),
	tax: () =>
		editor(
			'Property tax',
			select('Tax source', [
				'Use property tax · Austin sales tax',
				'Override for this job',
				'No tax'
			]) + '<p>Changing this job’s override does not change the property’s saved rate.</p>',
			() => saveLocal()
		),
	review: () =>
		editor(
			'Request review',
			'<p>Send Emma Wilson a review request for this job.</p>' +
				select('Channel', ['Email · emma@example.com', 'SMS · ending 0148']) +
				area('Message', 'Thank you for choosing Oak & Stone. We would love your feedback.'),
			() => saveLocal('Review request simulated. Nothing was sent.'),
			'Send preview'
		),
	search: () => {
		open(
			'Search Uplift',
			field('Search clients, jobs, quotes and invoices', 'Backyard') +
				'<div id="search-results">' +
				button('Job #1042 · Backyard transformation', 'close') +
				'</div>'
		);
	},
	notifications: () =>
		open(
			'Notifications',
			'<div class="detail-row"><div><strong>Visit tomorrow</strong><small>Patio installation · Marcus & Alex</small></div></div><div class="detail-row"><div><strong>Invoice reminder</strong><small>Review job #1042 on Oct 14</small></div></div>'
		),
	account: () =>
		menu('Jafar Khan · Business owner', [
			['Profile photo', 'profile'],
			['Password and security · destination preview', 'security'],
			['Sign out · preview', 'signout']
		]),
	profile: () =>
		editor('Profile photo · preview', field('Choose sample image', '', 'file'), () => saveLocal()),
	security: () =>
		open(
			'Password and security · destination preview',
			'<p>The real app opens Settings → Security.</p>'
		),
	signout: () =>
		confirm('Sign out · preview', 'This demo keeps you on the preview page.', () =>
			saveLocal('Sign-out preview complete. Your app session is unchanged.')
		),
	'add-new': () => open('Add New', '<p>Nothing to create yet.</p>'),
	theme: () =>
		open(
			'Theme control · preview',
			'<p>The current app supports light and dark themes. The new dark design is awaiting its own design approval, so this demo shows the approved light design.</p>'
		),
	workspace: () =>
		open(
			'Oak & Stone',
			'<p>Contractor workspace · Business owner</p><p>Workspace identity preview.</p>'
		),
	retry: () => {
		$('#scenario').value = 'populated';
		applyScenario('populated');
	}
};
function visitEditor(multiple, editing = false) {
	editor(
		editing ? 'Edit this visit' : multiple ? 'Add multiple visits' : 'Add a visit',
		field('Visit title', 'Patio installation') +
			field('Date', '2026-10-12', 'date') +
			(multiple
				? field('Last date', '2026-10-14', 'date') + select('Repeat', ['Every day', 'Picked dates'])
				: '') +
			check('Schedule later') +
			check('Anytime') +
			field('Start time', '08:00', 'time') +
			field('End time', '16:00', 'time') +
			check('Marcus Reed', true) +
			check('Alex Lee', true) +
			area('Instructions', 'Lay stone pavers and finish edging') +
			check('Notify customer (preview only)') +
			(scenario === 'recurring' ? field('Visit quantity', '1', 'number') : ''),
		() => {
			if (!editing) {
				const row = $('#visits .visit')?.cloneNode(true);
				if (row) {
					row.querySelector('h3').textContent = $('#preview-body input').value;
					$('#visits').append(row);
				} else
					$('#visits').insertAdjacentHTML(
						'beforeend',
						'<p class="panel__body">New sample visit · Oct 12</p>'
					);
			}
			saveLocal('Visit saved in preview only. No notification sent.');
		},
		'Save visit preview'
	);
}
// Wire original concept affordances by their section and labels.
$$('.page-heading__actions button').forEach(
	(b, i) => (b.dataset.action = ['edit-job', 'more', 'invoice'][i])
);
$('#visits .panel__heading button').dataset.action = 'add-visit';
$('#scope .panel__heading button').dataset.action = 'scope';
$('.instructions .panel__heading button').dataset.action = 'instructions';
$('.search').dataset.action = 'search';
$('.notification').dataset.action = 'notifications';
$('.sidebar__profile').dataset.action = 'account';
$('.sidebar__workspace').dataset.action = 'workspace';
$$('#visits .visit').forEach((v) => {
	v.tabIndex = 0;
	v.setAttribute('role', 'button');
	v.setAttribute('aria-label', 'Open ' + v.querySelector('h3').textContent);
	v.dataset.action = 'visit-menu';
});
$('.client .panel__heading a')?.setAttribute('data-destination', 'Client profile');
$$('.client a').forEach((a) => {
	if (!a.dataset.destination)
		a.dataset.destination = a.textContent.includes('directions') ? 'Directions' : 'Client contact';
});
$('#activity .text-link').dataset.action = 'history';
const baseline = $('#job-surface').innerHTML;
function applyScenario(value) {
	discard();
	scenario = value;
	selectedVisit = null;
	$('#job-surface').innerHTML = baseline;
	$('#load-state').hidden = true;
	$('#job-surface').hidden = false;
	$('#scenario-note').textContent = '';
	// Rebind title listener after scenario reset.
	$('#title-draft').addEventListener('input', (e) => {
		const v = e.target.value.trim();
		if (v && v !== storedTitle)
			staged.set('title', {
				value: v,
				apply: (value) => {
					storedTitle = value;
					$('#job-title').textContent = value;
				}
			});
		else staged.delete('title');
		draft();
	});
	$('#job-title').textContent = storedTitle;
	$('#billable').hidden = !['recurring', 'period'].includes(value);
	if (['loading', 'error'].includes(value)) {
		$('#job-surface').hidden = true;
		$('#load-state').hidden = false;
		$('#load-state').innerHTML =
			value === 'loading'
				? '<p role="status">Loading job…</p><div class="skeleton"></div><div class="skeleton"></div>'
				: '<section class="panel empty-state" role="alert"><strong>This job could not be loaded</strong><p>Your changes are safe. Try loading the job again.</p>' +
					button('Try again', 'retry') +
					'</section>';
		return;
	}
	if (value === 'empty') {
		[
			'labor',
			'expenses',
			'checklists',
			'notes',
			'files',
			'signatures',
			'report',
			'discount',
			'reminders'
		].forEach((id) => {
			const body = $(`#${id} .panel__body`);
			body.innerHTML = `<div class="empty-state"><strong>No ${id === 'report' ? 'work report' : id} yet</strong><p>Use the section action to add the first one.</p></div>`;
		});
		$$('#visits .visit').forEach((x) => x.remove());
		$('#visits').insertAdjacentHTML(
			'beforeend',
			'<div class="empty-state"><strong>No visits yet</strong><p>Add the days your crew will be on site.</p></div>'
		);
		$('#scope tbody').innerHTML = '<tr><td colspan="4">No products or services yet.</td></tr>';
		$$('.totals span:last-child,.totals strong:last-child,#job-total dd,#costing dd').forEach(
			(x) => (x.textContent = '$0.00')
		);
		$('.summary__item > strong').textContent = '$0.00';
		$('.summary__item small').textContent = 'No priced scope yet';
		$('#billing-basis').textContent = '$0.00 for the whole job';
		$$('.summary__item')[1].innerHTML = '<span>NEXT VISIT</span><strong>Not scheduled</strong>';
		$$('.summary__item')[3].innerHTML = '<span>VISIT PROGRESS</span><strong>0 visits</strong>';
		$('.instructions > p').textContent = 'No instructions yet.';
		$('#payment-stages').innerHTML = button('Add payment schedule', 'stages');
		$('#tax .panel__body').innerHTML = '<p>No tax configured.</p>';
		$('#activity .activity').innerHTML = '<p>Job created · Oct 10</p>';
	}
	if (['recurring', 'period', 'asneeded'].includes(value)) {
		const period = value === 'period';
		$('.page-heading__meta > span:last-child').textContent = 'Recurring job';
		$('#job-title').textContent = 'Garden care agreement';
		$('#billing-basis').textContent = period
			? '$500.00 each month regardless of visits'
			: '$120.00 per completed visit';
		$('#billing-timing').textContent = period ? 'At month end' : 'After every completed visit';
		$('#payment-stages').hidden = true;
		$('#cost-window').textContent = 'Last 30 days · Sep 11 – Oct 10, 2026';
		$('#costing .panel__body').innerHTML =
			'<p class="subtle">Last 30 days · Sep 11 – Oct 10, 2026</p><p>' +
			(period ? '1 billing period · Revenue $500.00' : '4 completed visits · Revenue $480.00') +
			'</p><p>Item cost $80.00 · Labor $120.00 · Expenses $20.00</p><p>Profit ' +
			(period ? '$280.00 · Margin 56%' : '$260.00 · Margin 54.2%') +
			'</p>';
		$('.summary__item > strong').textContent = period ? '$500.00' : '$120.00';
		$('.summary__item small').textContent = period ? 'Per billing period' : 'Per completed visit';
		$('#scope tbody').innerHTML =
			'<tr><td><strong>Garden care</strong><small>Pruning, mowing and seasonal care</small></td><td>1</td><td>' +
			(period ? '$500.00' : '$120.00') +
			'</td><td>' +
			(period ? '$500.00' : '$120.00') +
			'</td></tr>';
		$('#scope .totals').hidden = true;
		$('#job-total .panel__body').innerHTML =
			'<p>' +
			(period ? '$500.00 per billing period' : '$120.00 per visit') +
			'</p><p class="subtle">Amounts shown are for this pricing unit, not the lifetime agreement.</p>';
		$('#discount .panel__body').innerHTML = '<p>No discount applied.</p>';
		$('#tax .panel__body').innerHTML = '<p>No tax applied in this sample.</p>';
		$('#visits .panel__heading').insertAdjacentHTML(
			'afterend',
			'<div class="panel__body recurrence-summary">Weekly on Mondays · Oct 5 – Dec 28, 2026 ' +
				button('Edit all visits', 'recurrence') +
				'</div>'
		);
		$('#billable h2').textContent = period ? 'Periods ready to bill' : 'Visits ready to bill';
		$('#billable-content').innerHTML =
			check(period ? 'September · $500.00' : 'Oct 9 · Garden care · $120.00', true) +
			button('Create invoice', 'invoice');
		if (value === 'asneeded') {
			$$('.recurrence-summary,#visits .visit').forEach((x) => x.remove());
			$('#visits').insertAdjacentHTML(
				'beforeend',
				'<div class="empty-state"><strong>Dispatched as needed</strong><p>No set schedule. Add a visit whenever work comes up.</p></div>'
			);
			$$('.summary__item')[1].innerHTML = '<span>NEXT VISIT</span><strong>As needed</strong>';
		}
	}
	if (value === 'closed') {
		$('.page-heading__meta .badge').textContent = 'Closed';
		$('#scenario-note').textContent =
			'Completed work is preserved. Team managers may correct costs and records.';
		$$('#visits .visit:not(.visit--complete)').forEach((x) => x.remove());
		$('#visits .panel__heading button').hidden = true;
		$('.page-heading__actions').innerHTML =
			button('Reopen job', 'reopen') +
			button('More', 'more') +
			button('Create invoice', 'invoice', true);
		$('#signatures .panel__heading button').hidden = true;
		$('#checklists .panel__actions').hidden = true;
		$$('.summary__item')[1].innerHTML = '<span>NEXT VISIT</span><strong>None · closed</strong>';
		$$('.summary__item')[3].innerHTML = '<span>VISIT PROGRESS</span><strong>1 completed</strong>';
		$('#cost-window').textContent = 'Final costs · Only your team sees this';
		$('#costing .panel__body').insertAdjacentHTML('beforeend', '<p>Final margin · 57.2%</p>');
	}
	if (value === 'restricted') {
		$('#scenario-note').textContent =
			'Field member · Assigned job · Prices and internal costs are hidden. You can record your own work.';
		$$('.money-section,.cost-section').forEach((x) => (x.hidden = true));
		$('#labor').hidden = false;
		$('#expenses').hidden = false;
		$('#labor .panel__body').innerHTML =
			'<div class="detail-row"><div><strong>Your hours · Marcus Reed</strong><small>Oct 9 · Site preparation · 8h</small></div><div>' +
			button('Edit', 'edit-hours') +
			button('Remove', 'remove-hours') +
			'</div></div><p class="subtle">Your hours: 8h · Hourly costs are hidden</p>';
		$('#expenses .panel__body').innerHTML =
			'<div class="detail-row"><div><strong>Your expense · Disposal fee</strong><small>Oct 9 · Not reimbursable</small></div><div>' +
			button('Edit', 'expense') +
			'</div></div><p class="subtle">Your expenses: 1 · Cost totals are hidden</p>';
		$('#checklists .panel__body').innerHTML =
			'<strong>Site safety & handover</strong><p class="subtle">4 questions · Answer on each visit</p>' +
			button('View answers', 'visit-records');
		$$('[data-action=remove-file],[data-action=recurrence]').forEach((e) => (e.hidden = true));
		$('.summary__item').hidden = true;
		$('.page-heading__actions').hidden = true;

		$('#scope .panel__heading button').hidden = true;
		$$('#scope tr').forEach((row) => [...row.children].slice(2).forEach((x) => (x.hidden = true)));
		$('#scope .totals').hidden = true;
		$$(
			'.owner-section,#checklists .panel__actions,#visits .panel__heading button,.instructions .panel__heading button,[data-action=review]'
		).forEach((x) => (x.hidden = true));
		$('#signatures .panel__body .money-section')?.remove();
		$('#notes .inline-actions').innerHTML = button('Add your own note', 'note');
	}
	if (value === 'long') {
		$('#job-title').textContent =
			'Complete backyard transformation, accessible garden paths and heritage stone restoration for the Wilson family residence';
		$('.client__identity h3').textContent = 'Emma Alexandra Wilson-Richardson';
		$('.instructions > p').textContent = (
			storedInstructions +
			' Please coordinate with the household before deliveries and protect the existing planting beds. '
		).repeat(5);
	}
	if (value === 'changed') {
		$('#signatures .badge').textContent = 'Job changed';
		$('#signatures .panel__body').insertAdjacentHTML(
			'beforeend',
			'<p class="subtle">The job has changed since this was signed. The old signature remains as history.</p>'
		);
		$('#report .panel__body').insertAdjacentHTML(
			'afterbegin',
			'<p class="subtle">This report changed after it was shared. Emma still has the old version. Copying an updated link turns the old one off.</p>'
		);
	}
	if (value === 'final') {
		$$('#visits .visit:not(.visit--complete)')
			.slice(1)
			.forEach((e) => e.remove());
		$('#scenario-note').textContent =
			'Final visit preview · Complete the remaining visit to see Finish job, return visit, and keep open.';
	}
	if (value === 'editing') editTitle();
}
$('#scenario').addEventListener('change', (e) => applyScenario(e.target.value));
document.addEventListener('click', (e) => {
	const destination = e.target.closest('[data-destination]');
	if (destination) {
		if (document.body.classList.contains('nav-open')) setNavigation(false);
		e.preventDefault();
		open(
			destination.dataset.destination + ' · destination preview',
			'<p>This navigation item opens its own page in the real app. This job demo keeps you here.</p>'
		);
		return;
	}
	const el = e.target.closest('[data-action]');
	if (el) {
		if (el.matches('.visit')) selectedVisit = el;
		e.preventDefault();
		actions[el.dataset.action]?.();
	} else if (e.target.closest('a[href="#"]')) {
		e.preventDefault();
		open('Navigation preview', '<p>This is a destination outside the job details demo.</p>');
	}
});
document.addEventListener('keydown', (e) => {
	if (e.key === 'Escape' && document.body.classList.contains('nav-open')) setNavigation(false);
	if (e.key === 'Tab' && document.body.classList.contains('nav-open')) {
		const links = $$('#navigation a,#navigation button').filter((e) => e.offsetWidth);
		if (e.shiftKey && document.activeElement === links[0]) {
			e.preventDefault();
			links.at(-1).focus();
		} else if (!e.shiftKey && document.activeElement === links.at(-1)) {
			e.preventDefault();
			links[0].focus();
		}
	}
	if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
		e.preventDefault();
		actions.search();
	}
	if (e.target.matches('.visit') && ['Enter', ' '].includes(e.key)) {
		e.preventDefault();
		selectedVisit = e.target;
		visitMenu();
	}
	if (dialog.open && $('#lightbox-photo')) {
		if (e.key === 'ArrowRight') actions['next-photo']();
		if (e.key === 'ArrowLeft') actions['previous-photo']();
	}
});
applyScenario('populated');

document.addEventListener('change', (e) => {
	if (
		dialog.open &&
		$('#preview-title').textContent === 'Collect signature' &&
		e.target === $('#preview-body select')
	) {
		const statement = $$('#preview-body p')[0];
		statement.textContent =
			e.target.value === 'Work completion'
				? 'I confirm that the work described in this job has been completed.'
				: e.target.value === 'Other'
					? 'I acknowledge the statement below.'
					: 'I authorize the work described in this job.';
	}
});
