/**
 * Cloud Tasks: priority / standard の2キューで年額優先を実体化
 */
import { CloudTasksClient, protos } from "@google-cloud/tasks";

const client = new CloudTasksClient();

const QUEUE_STANDARD = process.env.TASKS_QUEUE_STANDARD || "ai-standard";
const QUEUE_PRIORITY = process.env.TASKS_QUEUE_PRIORITY || "ai-priority";

function resolveQueueName(queueTier?: string): string {
  return queueTier === "priority" ? QUEUE_PRIORITY : QUEUE_STANDARD;
}

/** API・UI用。subscription_yearly → priority、それ以外 → standard */
export type QueueTierApi = "standard" | "priority";

export type EnqueueParams = {
  jobId: string;
  uid: string;
  plan: string;
  text: string;
  queueTier?: QueueTierApi;
};

export type AiJobOp = "lineStopper" | "rewrite" | "empathy";

export type EnqueueAiJobParams = {
  jobId: string;
  uid: string;
  plan: string;
  op: AiJobOp;
  text: string;
  queueTier?: QueueTierApi;
  /** rewrite 用: scene, purpose, audience, tone, isYearly */
  context?: Record<string, unknown>;
};

async function enqueueAiJobInternal(params: EnqueueAiJobParams): Promise<string> {
  const project = process.env.GCLOUD_PROJECT || process.env.CLOUD_TASKS_PROJECT || (await client.getProjectId());
  const location = process.env.CLOUD_TASKS_LOCATION || "asia-northeast1";
  const queue = resolveQueueName(params.queueTier);

  const parent = client.queuePath(project, location, queue);

  const workerUrl = process.env.WORKER_URL;
  if (!workerUrl) throw new Error("WORKER_URL is not set");

  const serviceAccountEmail = process.env.TASKS_OIDC_SERVICE_ACCOUNT;
  if (!serviceAccountEmail) throw new Error("TASKS_OIDC_SERVICE_ACCOUNT is not set");

  const payload = Buffer.from(JSON.stringify(params)).toString("base64");

  const task: protos.google.cloud.tasks.v2.ITask = {
    httpRequest: {
      httpMethod: "POST",
      url: workerUrl,
      headers: { "Content-Type": "application/json" },
      body: Buffer.from(JSON.stringify({ payload })),
      oidcToken: {
        serviceAccountEmail,
        audience: workerUrl,
      },
    },
  };

  const [response] = await client.createTask({ parent, task });
  return response.name!;
}

export async function enqueueLineStopperJob(params: EnqueueParams): Promise<string> {
  return enqueueAiJobInternal({ ...params, op: "lineStopper" });
}

export async function enqueueAiJob(params: EnqueueAiJobParams): Promise<string> {
  return enqueueAiJobInternal(params);
}
