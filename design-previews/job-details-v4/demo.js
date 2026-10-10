const editor = document.getElementById('editor');
const input = document.getElementById('editor-value');
let editKind = 'job';
let returnFocus;
function closeEditor() {
	editor.close();
	returnFocus?.focus();
}
document.querySelectorAll('[data-edit-job], [data-edit-instructions]').forEach((button) => {
	button.addEventListener('click', () => {
		returnFocus = button;
		editKind = button.hasAttribute('data-edit-job') ? 'job' : 'instructions';
		document.getElementById('editor-title').textContent =
			editKind === 'job' ? 'Edit job title' : 'Edit crew instructions';
		document.getElementById('editor-label').textContent =
			editKind === 'job' ? 'Job title' : 'Instructions for the crew';
		input.value =
			editKind === 'job'
				? document.querySelector('h1').textContent
				: [...document.querySelectorAll('.instructions p')].map((p) => p.textContent).join('\n\n');
		editor.showModal();
		input.focus();
	});
});
document.querySelectorAll('[data-close]').forEach((b) => b.addEventListener('click', closeEditor));
document.getElementById('editor-form').addEventListener('submit', (event) => {
	event.preventDefault();
	if (!input.value.trim()) {
		input.setCustomValidity('Enter a value.');
		input.reportValidity();
		return;
	}
	input.setCustomValidity('');
	if (editKind === 'job') document.querySelector('h1').textContent = input.value.trim();
	else {
		const box = document.querySelector('.instructions');
		box.replaceChildren();
		const p = document.createElement('p');
		p.textContent = input.value.trim();
		p.style.whiteSpace = 'pre-wrap';
		box.append(p);
	}
	closeEditor();
});
input.addEventListener('input', () => input.setCustomValidity(''));
editor.addEventListener('cancel', () => returnFocus?.focus());
const photoDialog = document.getElementById('photo-preview');
document.querySelectorAll('[data-photo]').forEach((b) =>
	b.addEventListener('click', () => {
		returnFocus = b;
		document.getElementById('photo-full').src = b.dataset.photo;
		photoDialog.showModal();
	})
);
document.querySelector('[data-photo-close]').addEventListener('click', () => {
	photoDialog.close();
	returnFocus?.focus();
});
photoDialog.addEventListener('cancel', () => returnFocus?.focus());
document
	.querySelectorAll(
		'button:not([data-edit-job]):not([data-edit-instructions]):not([data-photo]):not(dialog button), a[href="#"]'
	)
	.forEach((el) =>
		el.addEventListener('click', (e) => {
			e.preventDefault();
			const toast = document.getElementById('toast');
			toast.textContent = `Design preview — ${el.textContent.trim() || el.getAttribute('aria-label')} is not connected.`;
			toast.classList.add('toast--visible');
			clearTimeout(window.toastTimer);
			window.toastTimer = setTimeout(() => toast.classList.remove('toast--visible'), 2600);
		})
	);
const links = [...document.querySelectorAll('.tabs a')];
links.forEach((link) =>
	link.addEventListener('click', () => {
		links.forEach((a) => a.classList.remove('tabs__active'));
		link.classList.add('tabs__active');
	})
);
