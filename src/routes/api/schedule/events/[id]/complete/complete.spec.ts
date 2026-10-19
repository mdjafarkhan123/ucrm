import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';
vi.mock('$lib/server/access/permission', () => ({ requireOrganizationPermission: vi.fn() }));
const permission = vi.mocked(requireOrganizationPermission);
const id = '00000000-0000-4000-8000-000000000091';
const org = '00000000-0000-4000-8000-000000000092';
const original = '2026-10-19T08:00:00.000Z';
let results: { data: unknown; error: unknown }[];
const query = {
 update: vi.fn(), eq: vi.fn(), is: vi.fn(), select: vi.fn(), maybeSingle: vi.fn()
};
const from = vi.fn();
function request(body = '{}') {
 return { params: { id }, request: new Request(`http://localhost/api/schedule/events/${id}/complete`, {method:'POST',headers:{'content-type':'application/json'},body}),locals:{supabase:{from}} } as unknown as Parameters<typeof POST>[0];
}
beforeEach(() => {
 vi.clearAllMocks();
 permission.mockResolvedValue({auth:{organization:{id:org}}} as never);
 results = [{data:{id,completed_at:original},error:null}];
 from.mockReturnValue(query);
 for (const key of ['update','eq','is','select'] as const) query[key].mockReturnValue(query);
 query.maybeSingle.mockImplementation(async()=>results.shift());
});
describe('Schedule event completion',()=>{
 it('requires the schedule-write permission and never accesses data after refusal',async()=>{
  permission.mockResolvedValue({response:new Response(null,{status:403})} as never);
  const result=await POST(request());
  expect(result.status).toBe(403);
  expect(permission).toHaveBeenCalledWith(expect.anything(),'jobs.schedule');
  expect(from).not.toHaveBeenCalled();
 });
 it.each(['{','{"completed_at":"2000-01-01T00:00:00Z"}'])('rejects malformed or caller-supplied completion data: %s',async body=>{
  const result=await POST(request(body));
  expect(result.status).toBe(422);
  expect(from).not.toHaveBeenCalled();
 });
 it('completes only an open event in the active business and uses a server timestamp',async()=>{
  const result=await POST(request());
  expect(result.status).toBe(200);
  expect(query.eq).toHaveBeenCalledWith('organization_id',org);
  expect(query.eq).toHaveBeenCalledWith('id',id);
  expect(query.is).toHaveBeenCalledWith('completed_at',null);
  expect(Date.parse(query.update.mock.calls[0][0].completed_at)).not.toBeNaN();
 });
 it('returns the original timestamp on retries without rewriting a completed event',async()=>{
  results=[{data:null,error:null},{data:{id,completed_at:original},error:null}];
  const result=await POST(request());
  expect((await result.json()).event.completed_at).toBe(original);
  expect(query.update).toHaveBeenCalledTimes(1);
  expect(query.is).toHaveBeenCalledWith('completed_at',null);
 });
 it('does not expose a missing or another business’s event',async()=>{
  results=[{data:null,error:null},{data:null,error:null}];
  expect((await POST(request())).status).toBe(404);
  expect(query.eq.mock.calls.filter(([field])=>field==='organization_id')).toHaveLength(2);
 });
 it('reports a database failure rather than claiming completion',async()=>{
  results=[{data:null,error:{message:'write failed'}}];
  expect((await POST(request())).status).toBe(500);
 });
});
