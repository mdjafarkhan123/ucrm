<script lang="ts">
	import fileCertificateIcon from '@tabler/icons/outline/file-certificate.svg?raw';
	import OwnerSettingsForm from '$lib/components/jafar/OwnerSettingsForm.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Input from '$lib/components/ui/Input.svelte';
</script>

<OwnerSettingsForm
	title="Privacy policy"
	icon={fileCertificateIcon}
	fields={['privacy_policy_url', 'privacy_policy_version']}
>
	{#snippet children(draft, errors)}
		<SectionBlock title="Policy people agree to" form>
			<Input
				id="privacy-policy-url"
				type="url"
				label="Privacy-policy link"
				required
				maxlength={500}
				placeholder="https://"
				bind:value={draft.privacy_policy_url}
				invalid={Boolean(errors.privacy_policy_url)}
				errorMessage={errors.privacy_policy_url}
			/>
			<Input
				id="privacy-policy-version"
				label="Version"
				required
				maxlength={40}
				bind:value={draft.privacy_policy_version}
				invalid={Boolean(errors.privacy_policy_version)}
				errorMessage={errors.privacy_policy_version}
			/>
		</SectionBlock>
	{/snippet}

	{#snippet about()}
		<p>
			People applying for a package see this link and agree to the policy. Each application records
			the version they agreed to.
		</p>
		<p>
			Change the version whenever the policy’s wording changes, so new agreements are told apart.
		</p>
	{/snippet}
</OwnerSettingsForm>
