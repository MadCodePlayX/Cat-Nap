import { Router, type IRouter } from "express";
import { eq, sql } from "drizzle-orm";
import { db, productsTable, renderJobsTable } from "@workspace/db";
import {
  CreateProductBody,
  GetProductParams,
  GetProductResponse,
  UpdateProductParams,
  UpdateProductBody,
  AddProductImageParams,
  AddProductImageBody,
  ListProductsResponse,
  UpdateProductResponse,
  AddProductImageResponse,
  DeleteProductParams,
} from "@workspace/api-zod";

const router: IRouter = Router();

// Drizzle returns Date objects; Zod schemas expect ISO strings
function ser<T>(v: T): T { return JSON.parse(JSON.stringify(v)); }

router.get("/products", async (_req, res): Promise<void> => {
  const products = await db.select().from(productsTable).orderBy(productsTable.createdAt);
  res.json(ListProductsResponse.parse(ser(products)));
});

router.post("/products", async (req, res): Promise<void> => {
  const parsed = CreateProductBody.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.message });
    return;
  }
  const data = parsed.data;
  const [product] = await db.insert(productsTable).values({
    name: data.name,
    description: data.description ?? null,
    category: data.category,
    material: data.material ?? null,
    dimensionsL: data.dimensionsL ?? null,
    dimensionsW: data.dimensionsW ?? null,
    dimensionsH: data.dimensionsH ?? null,
    imageUrls: data.imageUrls ?? [],
    sourceUrl: data.sourceUrl ?? null,
  }).returning();
  res.status(201).json(GetProductResponse.parse(ser(product)));
});

router.get("/products/:id", async (req, res): Promise<void> => {
  const params = GetProductParams.safeParse(req.params);
  if (!params.success) {
    res.status(400).json({ error: params.error.message });
    return;
  }
  const [product] = await db.select().from(productsTable).where(eq(productsTable.id, params.data.id));
  if (!product) {
    res.status(404).json({ error: "Product not found" });
    return;
  }
  res.json(GetProductResponse.parse(ser(product)));
});

router.patch("/products/:id", async (req, res): Promise<void> => {
  const params = UpdateProductParams.safeParse(req.params);
  if (!params.success) {
    res.status(400).json({ error: params.error.message });
    return;
  }
  const parsed = UpdateProductBody.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.message });
    return;
  }
  const updates: Record<string, unknown> = {};
  const data = parsed.data;
  if (data.name != null) updates["name"] = data.name;
  if (data.description !== undefined) updates["description"] = data.description;
  if (data.category != null) updates["category"] = data.category;
  if (data.material !== undefined) updates["material"] = data.material;
  if (data.dimensionsL !== undefined) updates["dimensionsL"] = data.dimensionsL;
  if (data.dimensionsW !== undefined) updates["dimensionsW"] = data.dimensionsW;
  if (data.dimensionsH !== undefined) updates["dimensionsH"] = data.dimensionsH;
  if (data.imageUrls !== undefined) updates["imageUrls"] = data.imageUrls;
  if (data.sourceUrl !== undefined) updates["sourceUrl"] = data.sourceUrl;

  const [product] = await db.update(productsTable).set(updates).where(eq(productsTable.id, params.data.id)).returning();
  if (!product) {
    res.status(404).json({ error: "Product not found" });
    return;
  }
  res.json(UpdateProductResponse.parse(ser(product)));
});

router.delete("/products/:id", async (req, res): Promise<void> => {
  const params = DeleteProductParams.safeParse(req.params);
  if (!params.success) {
    res.status(400).json({ error: params.error.message });
    return;
  }
  const [product] = await db.delete(productsTable).where(eq(productsTable.id, params.data.id)).returning();
  if (!product) {
    res.status(404).json({ error: "Product not found" });
    return;
  }
  res.sendStatus(204);
});

router.post("/products/:id/images", async (req, res): Promise<void> => {
  const params = AddProductImageParams.safeParse(req.params);
  if (!params.success) {
    res.status(400).json({ error: params.error.message });
    return;
  }
  const parsed = AddProductImageBody.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.message });
    return;
  }
  const [existing] = await db.select().from(productsTable).where(eq(productsTable.id, params.data.id));
  if (!existing) {
    res.status(404).json({ error: "Product not found" });
    return;
  }
  const newUrls = [...(existing.imageUrls ?? []), parsed.data.imageUrl];
  const [product] = await db.update(productsTable).set({ imageUrls: newUrls }).where(eq(productsTable.id, params.data.id)).returning();
  res.json(AddProductImageResponse.parse(ser(product)));
});

export default router;
