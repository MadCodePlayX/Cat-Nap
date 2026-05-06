import { Router, type IRouter } from "express";
import healthRouter from "./health";
import productsRouter from "./products";
import jobsRouter from "./jobs";
import workersRouter from "./workers";
import statsRouter from "./stats";

const router: IRouter = Router();

router.use(healthRouter);
router.use(productsRouter);
router.use(jobsRouter);
router.use(workersRouter);
router.use(statsRouter);

export default router;
