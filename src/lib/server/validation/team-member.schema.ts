import { z } from 'zod';
import { JAFAR_AREAS, SENSITIVE_ACTIONS, TEAM_ROLES } from '$lib/jafar/team-access';

// Jafar business D1: the Jafar Panel's teammates (ADR 0008). Passwords follow the contractor login rule,
// 8 to 72 characters (Jafar, 2026-10-07); 72 is bcrypt's limit.

const teamPasswordSchema = z
	.string()
	.min(8, 'Use at least 8 characters for the password.')
	.max(72, 'Use no more than 72 characters for the password.')
	.refine((value) => new TextEncoder().encode(value).length <= 72, {
		message: 'Use a shorter password.'
	});

const linkTokenSchema = z
	.string()
	.trim()
	.regex(/^[A-Za-z0-9_-]{43}$/, 'This link is not complete. Open it again from your email.');

export const teamInviteSchema = z.object({
	email: z.string().trim().toLowerCase().email('Enter a valid email address.').max(254),
	role: z.enum(TEAM_ROLES, { message: 'Choose a role.' })
});

export const teamJoinSchema = z
	.object({
		token: linkTokenSchema,
		full_name: z
			.string()
			.trim()
			.min(1, 'Enter your name.')
			.max(120, 'Use no more than 120 characters.'),
		password: teamPasswordSchema,
		password_confirmation: z.string().min(1, 'Confirm your password.').max(72)
	})
	.refine((value) => value.password === value.password_confirmation, {
		message: 'The passwords do not match.',
		path: ['password_confirmation']
	});

export const teamPasswordResetRequestSchema = z.object({
	email: z.string().trim().toLowerCase().email('Enter a valid email address.').max(254)
});

export const teamPasswordResetCompleteSchema = z
	.object({
		token: linkTokenSchema,
		password: teamPasswordSchema,
		password_confirmation: z.string().min(1, 'Confirm your new password.').max(72)
	})
	.refine((value) => value.password === value.password_confirmation, {
		message: 'The passwords do not match.',
		path: ['password_confirmation']
	});

// D2: Jafar sets a teammate's role and the access they end up with; the server stores only what differs
// from the role. The revision is the one the editor loaded, so a save never overwrites a newer change.
export const teamAccessSaveSchema = z.object({
	role: z.enum(TEAM_ROLES, { message: 'Choose a role.' }),
	areas: z.partialRecord(z.enum(JAFAR_AREAS), z.enum(['look', 'work'])),
	actions: z.array(z.enum(SENSITIVE_ACTIONS)).max(SENSITIVE_ACTIONS.length),
	expected_access_revision: z.number().int().min(0)
});
