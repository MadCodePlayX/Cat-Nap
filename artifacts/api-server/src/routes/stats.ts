import { Router, type IRouter } from "express";
import { eq, count, desc } from "drizzle-orm";
import { db, productsTable, renderJobsTable, workersTable } from "@workspace/db";
import {
  GetDashboardStatsResponse,
  GetJobsByStatusResponse,
  GetRecentActivityResponse,
} from "@workspace/api-zod";

const router: IRouter = Router();

router.get("/stats/dashboard", async (_req, res): Promise<void> => {
  const [totalProducts] = await db.select({ count: count() }).from(productsTable);
  const [totalJobs] = await db.select({ count: count() }).from(renderJobsTable);
  const [completedJobs] = await db.select({ count: count() }).from(renderJobsTable).where(eq(renderJobsTable.status, "completed"));
  const [pendingJobs] = await db.select({ count: count() }).from(renderJobsTable).where(eq(renderJobsTable.status, "pending"));
  const [failedJobs] = await db.select({ count: count() }).from(renderJobsTable).where(eq(renderJobsTable.status, "failed"));
  const [activeWorkers] = await db.select({ count: count() }).from(workersTable).where(eq(workersTable.status, "online"));

  const total = totalJobs.count;
  const failed = failedJobs.count;
  const completed = completedJobs.count;
  const successRate = total > 0 ? Math.round((completed / total) * 100) : 0;

  res.json(GetDashboardStatsResponse.parse({
    totalProducts: totalProducts.count,
    totalJobs: total,
    completedJobs: completed,
    pendingJobs: pendingJobs.count,
    activeWorkers: activeWorkers.count,
    successRate,
  }));
});

router.get("/stats/jobs-by-status", async (_req, res): Promise<void> => {
  const statuses = ["pending", "claimed", "generating_3d", "compositing", "rendering_video", "completed", "failed"];
  const results = await Promise.all(
    statuses.map(async (status) => {
      const [row] = await db.select({ count: count() }).from(renderJobsTable).where(eq(renderJobsTable.status, status));
      return { status, count: row?.count ?? 0 };
    })
  );
  res.json(GetJobsByStatusResponse.parse(results));
});

router.get("/stats/recent-activity", async (_req, res): Promise<void> => {
  const recentJobs = await db
    .select({
      id: renderJobsTable.id,
      status: renderJobsTable.status,
      productId: renderJobsTable.productId,
      createdAt: renderJobsTable.createdAt,
      updatedAt: renderJobsTable.updatedAt,
    })
    .from(renderJobsTable)
    .orderBy(desc(renderJobsTable.updatedAt))
    .limit(20);

  const activities = recentJobs.map((job, idx) => ({
    id: idx + 1,
    type: job.status === "completed" ? "completed" : job.status === "failed" ? "failed" : "job_update",
    label: `Job #${job.id} — ${job.status.replace(/_/g, " ")}`,
    detail: `Product #${job.productId}`,
    timestamp: job.updatedAt.toISOString(),
  }));

  res.json(GetRecentActivityResponse.parse(activities));
});

export default router;
