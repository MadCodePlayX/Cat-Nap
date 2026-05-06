import { Router, type IRouter } from "express";
import { eq } from "drizzle-orm";
import { db, workersTable } from "@workspace/db";
import {
  RegisterWorkerBody,
  WorkerHeartbeatParams,
  ListWorkersResponse,
  WorkerHeartbeatResponse,
} from "@workspace/api-zod";

const router: IRouter = Router();

router.get("/workers", async (_req, res): Promise<void> => {
  const workers = await db.select().from(workersTable).orderBy(workersTable.createdAt);
  res.json(ListWorkersResponse.parse(workers));
});

router.post("/workers", async (req, res): Promise<void> => {
  const parsed = RegisterWorkerBody.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.message });
    return;
  }
  const [worker] = await db.insert(workersTable).values({
    name: parsed.data.name,
    gpuModel: parsed.data.gpuModel ?? null,
    status: "online",
    lastHeartbeat: new Date(),
  }).returning();
  res.status(201).json(worker);
});

router.post("/workers/:id/heartbeat", async (req, res): Promise<void> => {
  const params = WorkerHeartbeatParams.safeParse(req.params);
  if (!params.success) {
    res.status(400).json({ error: params.error.message });
    return;
  }
  const [worker] = await db.update(workersTable).set({
    status: "online",
    lastHeartbeat: new Date(),
  }).where(eq(workersTable.id, params.data.id)).returning();
  if (!worker) {
    res.status(404).json({ error: "Worker not found" });
    return;
  }
  res.json(WorkerHeartbeatResponse.parse(worker));
});

export default router;
