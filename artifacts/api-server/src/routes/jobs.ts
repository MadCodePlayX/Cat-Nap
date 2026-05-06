import { Router, type IRouter } from "express";
import { eq, and, desc } from "drizzle-orm";
import { db, renderJobsTable, productsTable } from "@workspace/db";
import {
  CreateJobBody,
  GetJobParams,
  DeleteJobParams,
  UpdateJobStatusParams,
  UpdateJobStatusBody,
  ListJobsQueryParams,
  ListJobsResponse,
  GetJobResponse,
  UpdateJobStatusResponse,
} from "@workspace/api-zod";

const router: IRouter = Router();

// Drizzle returns Date objects and nulls; Zod schemas expect ISO strings and undefined
function ser<T>(v: T): T {
  return JSON.parse(JSON.stringify(v), (_k, val) => (val === null ? undefined : val));
}

async function enrichJob(job: typeof renderJobsTable.$inferSelect) {
  const [product] = await db.select({ name: productsTable.name }).from(productsTable).where(eq(productsTable.id, job.productId));
  return { ...job, productName: product?.name ?? "Unknown" };
}

router.get("/jobs/next", async (_req, res): Promise<void> => {
  const [job] = await db
    .select()
    .from(renderJobsTable)
    .where(eq(renderJobsTable.status, "pending"))
    .orderBy(desc(renderJobsTable.priority), renderJobsTable.createdAt)
    .limit(1);
  if (!job) {
    res.json({ job: null });
    return;
  }
  const enriched = await enrichJob(job);
  res.json({ job: GetJobResponse.parse(ser(enriched)) });
});

router.get("/jobs", async (req, res): Promise<void> => {
  const params = ListJobsQueryParams.safeParse(req.query);
  if (!params.success) {
    res.status(400).json({ error: params.error.message });
    return;
  }
  const conditions = [];
  if (params.data.status) {
    conditions.push(eq(renderJobsTable.status, params.data.status));
  }
  if (params.data.productId != null) {
    conditions.push(eq(renderJobsTable.productId, params.data.productId));
  }
  const jobs = await db
    .select()
    .from(renderJobsTable)
    .where(conditions.length > 0 ? and(...conditions) : undefined)
    .orderBy(desc(renderJobsTable.createdAt));

  const enriched = await Promise.all(jobs.map(enrichJob));
  res.json(ListJobsResponse.parse(ser(enriched)));
});

router.post("/jobs", async (req, res): Promise<void> => {
  const parsed = CreateJobBody.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.message });
    return;
  }
  const [product] = await db.select().from(productsTable).where(eq(productsTable.id, parsed.data.productId));
  if (!product) {
    res.status(400).json({ error: "Product not found" });
    return;
  }
  const [job] = await db.insert(renderJobsTable).values({
    productId: parsed.data.productId,
    sceneType: parsed.data.sceneType,
    animalType: parsed.data.animalType,
    priority: parsed.data.priority ?? 0,
    status: "pending",
  }).returning();
  const enriched = await enrichJob(job);
  res.status(201).json(GetJobResponse.parse(ser(enriched)));
});

router.get("/jobs/:id", async (req, res): Promise<void> => {
  const params = GetJobParams.safeParse(req.params);
  if (!params.success) {
    res.status(400).json({ error: params.error.message });
    return;
  }
  const [job] = await db.select().from(renderJobsTable).where(eq(renderJobsTable.id, params.data.id));
  if (!job) {
    res.status(404).json({ error: "Job not found" });
    return;
  }
  const enriched = await enrichJob(job);
  res.json(GetJobResponse.parse(ser(enriched)));
});

router.delete("/jobs/:id", async (req, res): Promise<void> => {
  const params = DeleteJobParams.safeParse(req.params);
  if (!params.success) {
    res.status(400).json({ error: params.error.message });
    return;
  }
  const [job] = await db.delete(renderJobsTable).where(eq(renderJobsTable.id, params.data.id)).returning();
  if (!job) {
    res.status(404).json({ error: "Job not found" });
    return;
  }
  res.sendStatus(204);
});

router.patch("/jobs/:id/status", async (req, res): Promise<void> => {
  const params = UpdateJobStatusParams.safeParse(req.params);
  if (!params.success) {
    res.status(400).json({ error: params.error.message });
    return;
  }
  const parsed = UpdateJobStatusBody.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.message });
    return;
  }
  const data = parsed.data;
  const updates: Record<string, unknown> = { status: data.status };
  if (data.stage !== undefined) updates["stage"] = data.stage;
  if (data.workerId !== undefined) updates["workerId"] = data.workerId;
  if (data.modelUrl !== undefined) updates["modelUrl"] = data.modelUrl;
  if (data.videoUrl !== undefined) updates["videoUrl"] = data.videoUrl;
  if (data.thumbnailUrl !== undefined) updates["thumbnailUrl"] = data.thumbnailUrl;
  if (data.errorMessage !== undefined) updates["errorMessage"] = data.errorMessage;
  if (data.progressPct !== undefined) updates["progressPct"] = data.progressPct;
  if (data.completedAt !== undefined) updates["completedAt"] = data.completedAt ? new Date(data.completedAt) : null;
  if (data.status === "completed" && !data.completedAt) updates["completedAt"] = new Date();

  const [job] = await db.update(renderJobsTable).set(updates).where(eq(renderJobsTable.id, params.data.id)).returning();
  if (!job) {
    res.status(404).json({ error: "Job not found" });
    return;
  }
  const enriched = await enrichJob(job);
  res.json(UpdateJobStatusResponse.parse(ser(enriched)));
});

export default router;
