import { pgTable, text, serial, timestamp, integer } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod/v4";
import { productsTable } from "./products";
import { workersTable } from "./workers";

export const renderJobsTable = pgTable("render_jobs", {
  id: serial("id").primaryKey(),
  productId: integer("product_id").notNull().references(() => productsTable.id, { onDelete: "cascade" }),
  status: text("status").notNull().default("pending"),
  stage: text("stage"),
  sceneType: text("scene_type").notNull(),
  animalType: text("animal_type").notNull(),
  priority: integer("priority").notNull().default(0),
  workerId: integer("worker_id").references(() => workersTable.id, { onDelete: "set null" }),
  modelUrl: text("model_url"),
  videoUrl: text("video_url"),
  thumbnailUrl: text("thumbnail_url"),
  errorMessage: text("error_message"),
  progressPct: integer("progress_pct"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow().$onUpdate(() => new Date()),
  completedAt: timestamp("completed_at", { withTimezone: true }),
});

export const insertRenderJobSchema = createInsertSchema(renderJobsTable).omit({ id: true, createdAt: true, updatedAt: true });
export type InsertRenderJob = z.infer<typeof insertRenderJobSchema>;
export type RenderJob = typeof renderJobsTable.$inferSelect;
