import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { ReceiptRule } from '@aws-sdk/client-ses';

const send = vi.fn();

vi.mock('@aws-sdk/client-ses', async (importOriginal) => {
	const actual = await importOriginal<typeof import('@aws-sdk/client-ses')>();
	return {
		...actual,
		SESClient: vi.fn(function () {
			return { send };
		})
	};
});

vi.mock('./ses-env', async (importOriginal) => {
	const actual = await importOriginal<typeof import('./ses-env')>();
	return {
		...actual,
		getSesEnv: () => ({
			AWS_SES_REGION: 'us-east-1',
			AWS_SES_ACCESS_KEY_ID: 'key',
			AWS_SES_SECRET_ACCESS_KEY: 'secret',
			AWS_SES_EVENT_SNS_TOPIC_ARN: 'arn:aws:sns:us-east-1:123456789012:events',
			accountId: '123456789012'
		})
	};
});

const { reconcileSesReceiptRule } = await import('./ses');
const { CreateReceiptRuleCommand, DescribeReceiptRuleCommand, UpdateReceiptRuleCommand } =
	await import('@aws-sdk/client-ses');

const TARGET = {
	bucketName: 'ucrm-ses-inbound-mime',
	objectKeyPrefix: 'org-1/',
	topicArn: 'arn:aws:sns:us-east-1:123456789012:inbound'
};
const DOMAIN = 'reply.example.com';

// The inbound worker only accepts S3-action notifications (bucket + object key). The rule must therefore
// store the MIME with ONE S3 action that notifies the topic itself -- never a second SNS action.
const EXPECTED_ACTIONS = [
	{
		S3Action: {
			BucketName: TARGET.bucketName,
			ObjectKeyPrefix: TARGET.objectKeyPrefix,
			TopicArn: TARGET.topicArn
		}
	}
];

function notFound() {
	return Object.assign(new Error('not found'), { name: 'RuleDoesNotExistException' });
}

function sentOf(type: new (...args: never[]) => unknown) {
	return send.mock.calls.map(([command]) => command).filter((command) => command instanceof type);
}

beforeEach(() => {
	send.mockReset();
});

describe('reconcileSesReceiptRule', () => {
	it('creates a missing rule with one S3 action that notifies the topic', async () => {
		send.mockImplementation(async (command) => {
			if (command instanceof DescribeReceiptRuleCommand) throw notFound();
			return {};
		});

		await reconcileSesReceiptRule('set', 'rule', DOMAIN, TARGET);

		const [create] = sentOf(CreateReceiptRuleCommand) as InstanceType<
			typeof CreateReceiptRuleCommand
		>[];
		expect(create.input.Rule?.Recipients).toEqual([DOMAIN]);
		expect(create.input.Rule?.Actions).toEqual(EXPECTED_ACTIONS);
	});

	it('replaces the old S3 + separate SNS action shape', async () => {
		const legacy: ReceiptRule = {
			Name: 'rule',
			Enabled: true,
			Recipients: [DOMAIN],
			Actions: [
				{ S3Action: { BucketName: TARGET.bucketName, ObjectKeyPrefix: TARGET.objectKeyPrefix } },
				{ SNSAction: { TopicArn: TARGET.topicArn, Encoding: 'UTF-8' } }
			]
		};
		send.mockImplementation(async (command) =>
			command instanceof DescribeReceiptRuleCommand ? { Rule: legacy } : {}
		);

		await reconcileSesReceiptRule('set', 'rule', DOMAIN, TARGET);

		const [update] = sentOf(UpdateReceiptRuleCommand) as InstanceType<
			typeof UpdateReceiptRuleCommand
		>[];
		expect(update.input.Rule?.Actions).toEqual(EXPECTED_ACTIONS);
	});

	it('leaves a rule already in the desired shape untouched', async () => {
		const current: ReceiptRule = {
			Name: 'rule',
			Enabled: true,
			Recipients: [DOMAIN],
			Actions: EXPECTED_ACTIONS
		};
		send.mockImplementation(async (command) =>
			command instanceof DescribeReceiptRuleCommand ? { Rule: current } : {}
		);

		await reconcileSesReceiptRule('set', 'rule', DOMAIN, TARGET);

		expect(sentOf(UpdateReceiptRuleCommand)).toHaveLength(0);
		expect(sentOf(CreateReceiptRuleCommand)).toHaveLength(0);
	});
});
