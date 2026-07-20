import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.43.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const PROMPT_VERSION = "v2";

type ActionType =
  | "task_overdue"
  | "task_due_today"
  | "task_stuck"
  | "invoice_overdue"
  | "invoice_due_today"
  | "bill_overdue"
  | "bill_due_today"
  | "budget_overrun"
  | "messages_unread"
  | "project_due_soon";

interface ActionCandidate {
  type: ActionType;
  severity: number;
  title: string;
  summary: string;
  action: string;
  projectName?: string;
  dueDate?: string;
}

interface SummaryRequest {
  workspace_id: string;
  user_id: string;
  date?: string; // YYYY-MM-DD
  force?: boolean;
}

interface SourceData {
  date: string;
  actionCandidates: ActionCandidate[];
  tasks: {
    totalAssigned: number;
    overdueCount: number;
    dueTodayCount: number;
    dueSoonCount: number;
    stuckCount: number;
    highPriorityOverdueCount: number;
    overdue: Array<{ title: string; projectName?: string; dueDate: string }>;
    dueToday: Array<{ title: string; projectName?: string; dueDate: string }>;
    dueSoon: Array<{ title: string; projectName?: string; dueDate: string }>;
  };
  messages: {
    unreadTotal: number;
    conversations: Array<{ name: string; lastMessageAt?: string }>;
  };
  projects: {
    updatedRecently: Array<{ name: string; updatedAt: string }>;
    dueSoon: Array<{ name: string; targetCompletionDate: string }>;
  };
  financials: {
    invoices: {
      dueTodayCount: number;
      overdueCount: number;
      dueTodayAmount: number;
      overdueAmount: number;
      items: Array<{ number: string; projectName?: string; dueDate: string; total: number }>;
    };
    bills: {
      dueTodayCount: number;
      overdueCount: number;
      dueTodayAmount: number;
      overdueAmount: number;
      items: Array<{ number: string; projectName?: string; dueDate: string; total: number }>;
    };
    budgetVariance: Array<{ projectName: string; projectedCost: number; committedCost: number; overByPercent: number }>;
  };
}

function getEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing environment variable: ${name}`);
  }
  return value;
}

function getDatePartsInTimeZone(date: Date, timeZone: string) {
  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  });
  const parts = formatter.formatToParts(date);
  const get = (type: string) => parts.find((p) => p.type === type)?.value || "";
  return {
    year: get("year"),
    month: get("month"),
    day: get("day"),
    hour: parseInt(get("hour"), 10),
    minute: parseInt(get("minute"), 10),
  };
}

function ymdFromParts(parts: { year: string; month: string; day: string }) {
  return `${parts.year}-${parts.month}-${parts.day}`;
}

function ymdToUtcDate(ymd: string): Date {
  return new Date(`${ymd}T00:00:00Z`);
}

function addDaysYmd(ymd: string, days: number): string {
  const date = ymdToUtcDate(ymd);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

function dateToYmdInTz(date: Date, timeZone: string): string {
  const parts = getDatePartsInTimeZone(date, timeZone);
  return ymdFromParts(parts);
}

function safeNumber(value: unknown): number {
  if (typeof value === "number") return value;
  if (typeof value === "string") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}

function getBooleanEnv(name: string, fallback = false): boolean {
  const raw = Deno.env.get(name);
  if (!raw) return fallback;
  const value = raw.trim().toLowerCase();
  return value === "1" || value === "true" || value === "yes" || value === "on";
}

function shouldLogActionDebug(summaryDate: string): boolean {
  if (!getBooleanEnv("DAILY_SUMMARY_DEBUG_ACTIONS", false)) {
    return false;
  }

  const untilYmd = Deno.env.get("DAILY_SUMMARY_DEBUG_ACTIONS_UNTIL")?.trim();
  if (!untilYmd) return true;
  return summaryDate <= untilYmd;
}

function logActionCandidatesDebug(
  workspaceId: string,
  userId: string,
  source: SourceData,
  stage: "input" | "result",
  provider?: string,
  status?: string,
) {
  if (!shouldLogActionDebug(source.date)) return;

  const payload = {
    event: "daily_summary_action_debug",
    stage,
    workspaceId,
    userId,
    date: source.date,
    provider: provider || null,
    status: status || null,
    topCandidates: source.actionCandidates.slice(0, 5).map((candidate) => ({
      type: candidate.type,
      severity: candidate.severity,
      title: candidate.title,
      projectName: candidate.projectName || null,
      dueDate: candidate.dueDate || null,
    })),
    totals: {
      overdueTasks: source.tasks.overdueCount,
      dueTodayTasks: source.tasks.dueTodayCount,
      stuckTasks: source.tasks.stuckCount,
      invoiceOverdue: source.financials.invoices.overdueCount,
      billOverdue: source.financials.bills.overdueCount,
      unreadMessages: source.messages.unreadTotal,
    },
  };

  console.log(JSON.stringify(payload));
}

function formatUsd(amount: number): string {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    maximumFractionDigits: 0,
  }).format(Math.max(0, amount));
}

function daysBetweenYmd(fromYmd: string, toYmd: string): number {
  const from = ymdToUtcDate(fromYmd).getTime();
  const to = ymdToUtcDate(toYmd).getTime();
  return Math.round((to - from) / (24 * 60 * 60 * 1000));
}

function buildActionCandidates(source: SourceData): ActionCandidate[] {
  const candidates: ActionCandidate[] = [];

  if (source.tasks.overdueCount > 0) {
    const sample = source.tasks.overdue[0];
    const highPriority = source.tasks.highPriorityOverdueCount;
    candidates.push({
      type: "task_overdue",
      severity: Math.min(100, 85 + source.tasks.overdueCount * 3 + highPriority * 4),
      title: `${source.tasks.overdueCount} overdue task(s)`,
      summary: `${source.tasks.overdueCount} overdue task(s)${sample ? `, including "${sample.title}"` : ""}.`,
      action: "Reschedule or complete overdue tasks first.",
      projectName: sample?.projectName,
      dueDate: sample?.dueDate,
    });
  }

  if (source.tasks.stuckCount > 0) {
    candidates.push({
      type: "task_stuck",
      severity: Math.min(95, 74 + source.tasks.stuckCount * 4),
      title: `${source.tasks.stuckCount} stuck task(s)`,
      summary: `${source.tasks.stuckCount} task(s) are marked stuck.`,
      action: "Clear blockers or reassign blocked tasks.",
    });
  }

  if (source.tasks.dueTodayCount > 0) {
    const sample = source.tasks.dueToday[0];
    candidates.push({
      type: "task_due_today",
      severity: Math.min(90, 66 + source.tasks.dueTodayCount * 3),
      title: `${source.tasks.dueTodayCount} task(s) due today`,
      summary: `${source.tasks.dueTodayCount} task(s) due today${sample ? `, including "${sample.title}"` : ""}.`,
      action: "Prioritize work due today.",
      projectName: sample?.projectName,
      dueDate: sample?.dueDate,
    });
  }

  if (source.financials.invoices.overdueCount > 0) {
    candidates.push({
      type: "invoice_overdue",
      severity: Math.min(99, 82 + source.financials.invoices.overdueCount * 3),
      title: `${source.financials.invoices.overdueCount} overdue invoice(s)`,
      summary: `${source.financials.invoices.overdueCount} overdue invoice(s) totaling about ${formatUsd(source.financials.invoices.overdueAmount)}.`,
      action: "Follow up on overdue invoices.",
    });
  }

  if (source.financials.invoices.dueTodayCount > 0) {
    candidates.push({
      type: "invoice_due_today",
      severity: Math.min(88, 65 + source.financials.invoices.dueTodayCount * 3),
      title: `${source.financials.invoices.dueTodayCount} invoice(s) due today`,
      summary: `${source.financials.invoices.dueTodayCount} invoice(s) due today totaling about ${formatUsd(source.financials.invoices.dueTodayAmount)}.`,
      action: "Send payment reminders for invoices due today.",
    });
  }

  if (source.financials.bills.overdueCount > 0) {
    candidates.push({
      type: "bill_overdue",
      severity: Math.min(95, 78 + source.financials.bills.overdueCount * 3),
      title: `${source.financials.bills.overdueCount} overdue bill(s)`,
      summary: `${source.financials.bills.overdueCount} overdue bill(s) totaling about ${formatUsd(source.financials.bills.overdueAmount)}.`,
      action: "Review and pay overdue bills.",
    });
  }

  if (source.financials.bills.dueTodayCount > 0) {
    candidates.push({
      type: "bill_due_today",
      severity: Math.min(85, 63 + source.financials.bills.dueTodayCount * 3),
      title: `${source.financials.bills.dueTodayCount} bill(s) due today`,
      summary: `${source.financials.bills.dueTodayCount} bill(s) due today totaling about ${formatUsd(source.financials.bills.dueTodayAmount)}.`,
      action: "Confirm approvals and pay bills due today.",
    });
  }

  if (source.financials.budgetVariance.length > 0) {
    const top = source.financials.budgetVariance[0];
    candidates.push({
      type: "budget_overrun",
      severity: Math.min(93, 60 + Math.round(top.overByPercent / 2)),
      title: `${top.projectName} over budget`,
      summary: `${top.projectName} is ${top.overByPercent.toFixed(0)}% over projected cost.`,
      action: "Review scope, pricing, and pending commitments.",
      projectName: top.projectName,
    });
  }

  if (source.messages.unreadTotal >= 5) {
    candidates.push({
      type: "messages_unread",
      severity: Math.min(80, 52 + Math.round(source.messages.unreadTotal / 2)),
      title: `${source.messages.unreadTotal} unread message(s)`,
      summary: `${source.messages.unreadTotal} unread message(s) across ${source.messages.conversations.length} conversation(s).`,
      action: "Triage unread messages that may block execution.",
    });
  }

  const nearestProject = source.projects.dueSoon
    .map((project) => ({ ...project, daysUntil: daysBetweenYmd(source.date, project.targetCompletionDate) }))
    .sort((a, b) => a.daysUntil - b.daysUntil)[0];

  if (nearestProject && nearestProject.daysUntil <= 3) {
    candidates.push({
      type: "project_due_soon",
      severity: 58 + Math.max(0, 3 - nearestProject.daysUntil) * 6,
      title: `${nearestProject.name} due soon`,
      summary: `${nearestProject.name} targets completion on ${nearestProject.targetCompletionDate}.`,
      action: "Validate critical path and owner readiness.",
      projectName: nearestProject.name,
      dueDate: nearestProject.targetCompletionDate,
    });
  }

  return candidates.sort((a, b) => b.severity - a.severity).slice(0, 8);
}

function buildFallbackSummary(source: SourceData): string {
  const actionBullets = source.actionCandidates
    .filter((candidate) => candidate.severity >= 55)
    .slice(0, 4)
    .map((candidate) => `- ${candidate.summary} ${candidate.action}`);
  return actionBullets.join("\n");
}

function buildQuietDaySummary(source: SourceData): string {
  const bullets: string[] = [];

  bullets.push("- No urgent actions need attention today.");

  if (source.tasks.totalAssigned > 0) {
    const taskParts: string[] = [];
    if (source.tasks.overdueCount > 0) {
      taskParts.push(`${source.tasks.overdueCount} overdue`);
    }
    if (source.tasks.dueTodayCount > 0) {
      taskParts.push(`${source.tasks.dueTodayCount} due today`);
    }
    if (source.tasks.dueSoonCount > 0) {
      taskParts.push(`${source.tasks.dueSoonCount} due in the next 7 days`);
    }

    if (taskParts.length > 0) {
      bullets.push(`- Assigned tasks: ${taskParts.join(", ")}.`);
    } else {
      bullets.push(`- Assigned tasks are under control across ${source.tasks.totalAssigned} tracked item(s).`);
    }
  } else {
    bullets.push("- You have no assigned tasks due or overdue.");
  }

  if (source.messages.unreadTotal > 0) {
    bullets.push(`- Inbox status: ${source.messages.unreadTotal} unread message(s) still need review.`);
  } else {
    bullets.push("- Inbox status: no unread conversations are waiting.");
  }

  if (source.projects.dueSoon.length > 0) {
    const nextProject = source.projects.dueSoon[0];
    bullets.push(`- Next project deadline: ${nextProject.name} targets ${nextProject.targetCompletionDate}.`);
  } else if (
    source.financials.invoices.overdueCount > 0 ||
    source.financials.bills.overdueCount > 0
  ) {
    bullets.push(
      `- Financial follow-up remains light: ${source.financials.invoices.overdueCount} overdue invoice(s) and ${source.financials.bills.overdueCount} overdue bill(s).`,
    );
  } else {
    bullets.push("- No near-term project deadlines or overdue financial items need attention.");
  }

  return bullets.slice(0, 4).join("\n");
}

async function callOpenRouter(prompt: string, system: string) {
  const apiKey = getEnv("OPENROUTER_API_KEY");
  const model = Deno.env.get("OPENROUTER_MODEL") || "z-ai/glm-4.5-air:free";

  const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      "HTTP-Referer": "https://example.com",
      "X-Title": "FieldFleet",
    },
    body: JSON.stringify({
      model,
      messages: [
        { role: "system", content: system },
        { role: "user", content: prompt },
      ],
      temperature: 0.4,
      max_tokens: 450,
    }),
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`OpenRouter error: ${response.status} ${error}`);
  }

  const data = await response.json();
  const content = data?.choices?.[0]?.message?.content;
  if (!content || typeof content !== "string") {
    throw new Error("OpenRouter response missing content");
  }

  return { content: content.trim(), model };
}

async function buildSourceData(
  supabase: ReturnType<typeof createClient>,
  workspaceId: string,
  userId: string,
  timeZone: string,
  summaryDate: string,
): Promise<SourceData> {
  const todayYmd = summaryDate;
  const next7Ymd = addDaysYmd(todayYmd, 7);

  // Tasks assigned to user
  const { data: assignees } = await supabase
    .from("task_assignees")
    .select("task_id")
    .eq("user_id", userId);

  const taskIds = (assignees || []).map((row) => row.task_id).filter(Boolean);
  let tasks: Array<any> = [];

  if (taskIds.length > 0) {
    const { data: taskRows } = await supabase
      .from("tasks")
      .select("id,title,due_date,is_complete,status,priority,project_id,projects(name)")
      .in("id", taskIds);

    tasks = taskRows || [];
  }

  const overdue: Array<{ title: string; projectName?: string; dueDate: string }> = [];
  const dueToday: Array<{ title: string; projectName?: string; dueDate: string }> = [];
  const dueSoon: Array<{ title: string; projectName?: string; dueDate: string }> = [];
  let stuckCount = 0;
  let highPriorityOverdueCount = 0;

  for (const task of tasks) {
    if (task.is_complete) continue;
    if (task.status === "stuck") stuckCount += 1;
    if (!task.due_date) continue;

    const dueDate = new Date(task.due_date);
    const dueYmd = dateToYmdInTz(dueDate, timeZone);
    const projectName = task.projects?.name as string | undefined;

    if (dueYmd < todayYmd) {
      overdue.push({ title: task.title, projectName, dueDate: dueYmd });
      if (task.priority === "high") highPriorityOverdueCount += 1;
    } else if (dueYmd === todayYmd) {
      dueToday.push({ title: task.title, projectName, dueDate: dueYmd });
    } else if (dueYmd <= next7Ymd) {
      dueSoon.push({ title: task.title, projectName, dueDate: dueYmd });
    }
  }

  // Messages / Conversations
  const { data: conversations } = await supabase
    .from("conversations")
    .select("id,participant_ids,participant_names,last_message_at,unread_counts")
    .eq("workspace_id", workspaceId)
    .contains("participant_ids", [userId]);

  const unreadConversations: Array<{ name: string; lastMessageAt?: string }> = [];
  let unreadTotal = 0;

  for (const conv of conversations || []) {
    const unreadCounts = conv.unread_counts || {};
    const unread = safeNumber(unreadCounts[userId] ?? 0);
    if (unread <= 0) continue;

    unreadTotal += unread;

    let name = "Conversation";
    const participantIds: string[] = conv.participant_ids || [];
    const names = conv.participant_names || {};
    const otherId = participantIds.find((id) => id !== userId);
    if (otherId && names[otherId]) {
      name = names[otherId];
    }

    unreadConversations.push({
      name,
      lastMessageAt: conv.last_message_at || undefined,
    });
  }

  unreadConversations.sort((a, b) => {
    const aTime = a.lastMessageAt ? new Date(a.lastMessageAt).getTime() : 0;
    const bTime = b.lastMessageAt ? new Date(b.lastMessageAt).getTime() : 0;
    return bTime - aTime;
  });

  // Projects
  const since = new Date();
  since.setHours(since.getHours() - 24);

  const { data: updatedProjects } = await supabase
    .from("projects")
    .select("id,name,status,updated_at,target_completion_date")
    .eq("workspace_id", workspaceId)
    .in("status", ["active", "awarded", "on_hold"])
    .gte("updated_at", since.toISOString());

  const { data: dueProjects } = await supabase
    .from("projects")
    .select("id,name,target_completion_date")
    .eq("workspace_id", workspaceId)
    .gte("target_completion_date", todayYmd)
    .lte("target_completion_date", next7Ymd);

  // Financials - invoices
  const { data: invoices } = await supabase
    .from("invoices")
    .select("id,invoice_number,status,due_date,total,project_id,projects(name)")
    .eq("workspace_id", workspaceId)
    .not("due_date", "is", null);

  const invoiceItems: Array<{ number: string; projectName?: string; dueDate: string; total: number }> = [];
  let invoiceDueToday = 0;
  let invoiceOverdue = 0;
  let invoiceDueTodayAmount = 0;
  let invoiceOverdueAmount = 0;

  for (const invoice of invoices || []) {
    if (invoice.status === "paid" || invoice.status === "cancelled") continue;
    const dueDate = invoice.due_date as string;
    const total = safeNumber(invoice.total);
    if (dueDate < todayYmd) {
      invoiceOverdue += 1;
      invoiceOverdueAmount += total;
      invoiceItems.push({
        number: invoice.invoice_number,
        projectName: invoice.projects?.name,
        dueDate,
        total,
      });
    } else if (dueDate === todayYmd) {
      invoiceDueToday += 1;
      invoiceDueTodayAmount += total;
      invoiceItems.push({
        number: invoice.invoice_number,
        projectName: invoice.projects?.name,
        dueDate,
        total,
      });
    }
  }

  // Financials - bills
  const { data: bills } = await supabase
    .from("bills")
    .select("id,bill_number,status,due_date,total,project_id,projects(name)")
    .eq("workspace_id", workspaceId)
    .not("due_date", "is", null);

  const billItems: Array<{ number: string; projectName?: string; dueDate: string; total: number }> = [];
  let billDueToday = 0;
  let billOverdue = 0;
  let billDueTodayAmount = 0;
  let billOverdueAmount = 0;

  for (const bill of bills || []) {
    if (bill.status === "paid" || bill.status === "void") continue;
    const dueDate = bill.due_date as string;
    const total = safeNumber(bill.total);
    if (dueDate < todayYmd) {
      billOverdue += 1;
      billOverdueAmount += total;
      billItems.push({
        number: bill.bill_number,
        projectName: bill.projects?.name,
        dueDate,
        total,
      });
    } else if (dueDate === todayYmd) {
      billDueToday += 1;
      billDueTodayAmount += total;
      billItems.push({
        number: bill.bill_number,
        projectName: bill.projects?.name,
        dueDate,
        total,
      });
    }
  }

  // Budget variance
  const { data: budgetItems } = await supabase
    .from("budget_items")
    .select("project_id,projected_cost,committed_cost")
    .eq("workspace_id", workspaceId);

  const budgetByProject = new Map<string, { projected: number; committed: number }>();

  for (const item of budgetItems || []) {
    if (!item.project_id) continue;
    const projected = safeNumber(item.projected_cost);
    const committed = safeNumber(item.committed_cost);
    const current = budgetByProject.get(item.project_id) || { projected: 0, committed: 0 };
    current.projected += projected;
    current.committed += committed;
    budgetByProject.set(item.project_id, current);
  }

  const overBudgetProjects = Array.from(budgetByProject.entries())
    .filter(([, values]) => values.projected > 0 && values.committed > values.projected * 1.05)
    .sort((a, b) => (b[1].committed - b[1].projected) - (a[1].committed - a[1].projected));

  let projectNameMap = new Map<string, string>();
  if (overBudgetProjects.length > 0) {
    const projectIds = overBudgetProjects.map(([id]) => id);
    const { data: projectNames } = await supabase
      .from("projects")
      .select("id,name")
      .in("id", projectIds);

    projectNameMap = new Map((projectNames || []).map((p: any) => [p.id, p.name]));
  }

  const budgetVariance = overBudgetProjects.slice(0, 5).map(([id, values]) => {
    const overByPercent = ((values.committed - values.projected) / values.projected) * 100;
    return {
      projectName: projectNameMap.get(id) || "Project",
      projectedCost: values.projected,
      committedCost: values.committed,
      overByPercent,
    };
  });

  const sourceData: SourceData = {
    date: todayYmd,
    actionCandidates: [],
    tasks: {
      totalAssigned: tasks.length,
      overdueCount: overdue.length,
      dueTodayCount: dueToday.length,
      dueSoonCount: dueSoon.length,
      stuckCount,
      highPriorityOverdueCount,
      overdue: overdue.slice(0, 3),
      dueToday: dueToday.slice(0, 3),
      dueSoon: dueSoon.slice(0, 3),
    },
    messages: {
      unreadTotal,
      conversations: unreadConversations.slice(0, 3),
    },
    projects: {
      updatedRecently: (updatedProjects || []).slice(0, 3).map((p: any) => ({
        name: p.name,
        updatedAt: p.updated_at,
      })),
      dueSoon: (dueProjects || []).slice(0, 3).map((p: any) => ({
        name: p.name,
        targetCompletionDate: p.target_completion_date,
      })),
    },
    financials: {
      invoices: {
        dueTodayCount: invoiceDueToday,
        overdueCount: invoiceOverdue,
        dueTodayAmount: invoiceDueTodayAmount,
        overdueAmount: invoiceOverdueAmount,
        items: invoiceItems.slice(0, 3),
      },
      bills: {
        dueTodayCount: billDueToday,
        overdueCount: billOverdue,
        dueTodayAmount: billDueTodayAmount,
        overdueAmount: billOverdueAmount,
        items: billItems.slice(0, 3),
      },
      budgetVariance,
    },
  };

  sourceData.actionCandidates = buildActionCandidates(sourceData);
  return sourceData;
}

function buildPrompt(source: SourceData): string {
  const input = {
    date: source.date,
    action_candidates: source.actionCandidates,
    support: {
      tasks: source.tasks,
      financials: source.financials,
      messages: source.messages,
      projects: source.projects,
    },
  };

  return `Today is ${source.date}.\n\nHere is the user's operational data in JSON:\n${JSON.stringify(input, null, 2)}\n\nWrite only action-required bullets. Return 0-4 bullets from highest to lowest severity using action_candidates first, and only if they require action now. Do not output "all clear", "no issues", or similar filler.`;
}

const systemPrompt = `You are a concise operations assistant for a construction management app.

Rules:
- Output only a Markdown bullet list (each line starts with "-")
- Return 1-4 bullets, max 120 words total
- If action_candidates are present, prioritize action-required items first
- If there are no urgent action items, provide a brief operational status summary instead of returning empty output
- Keep the tone factual and concise, not cheerful or verbose
- Use only the provided data; do not speculate
- Never output a blank bullet, placeholder bullet, or a bullet with only punctuation
- Avoid filler like "all clear" or "caught up" with no supporting detail`;

function normalizeSummaryMarkdown(content: string): string {
  const lines = content
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      if (/^no_actions$/i.test(line)) {
        return "NO_ACTIONS";
      }
      if (/^[-*•]/.test(line)) {
        return line.replace(/^[-*•]\s*/, "- ").trim();
      }
      return `- ${line}`;
    });

  const noisePatterns = [
    /^-\s*all caught up\.?$/i,
    /^-\s*no urgent items\.?$/i,
    /^-\s*no issues\.?$/i,
    /^-\s*caught up\.?$/i,
  ];

  const filtered = lines.filter((line) => {
    if (/^NO_ACTIONS$/i.test(line)) return false;
    const bulletBody = line.replace(/^-\s*/, "").trim();
    if (!bulletBody) return false;
    return !noisePatterns.some((pattern) => pattern.test(line));
  });

  if (filtered.length === 1 && /-?\s*no_actions/i.test(filtered[0])) {
    return "";
  }

  return filtered.slice(0, 4).join("\n");
}

async function generateSummary(
  supabase: ReturnType<typeof createClient>,
  workspaceId: string,
  userId: string,
  timeZone: string,
  summaryDate: string,
) {
  const sourceData = await buildSourceData(supabase, workspaceId, userId, timeZone, summaryDate);
  logActionCandidatesDebug(workspaceId, userId, sourceData, "input");

  if (sourceData.actionCandidates.length === 0) {
    return {
      summaryMarkdown: buildQuietDaySummary(sourceData),
      sourceData,
      provider: "fallback",
      model: null,
      status: "fallback",
      error: null,
    };
  }

  try {
    const { content, model } = await callOpenRouter(buildPrompt(sourceData), systemPrompt);
    const normalized = normalizeSummaryMarkdown(content);
    const fallback = buildFallbackSummary(sourceData);
    const summaryMarkdown =
      normalized || (sourceData.actionCandidates.length > 0 ? fallback : "");
    logActionCandidatesDebug(workspaceId, userId, sourceData, "result", "openrouter", "success");
    return {
      summaryMarkdown,
      sourceData,
      provider: normalized ? "openrouter" : sourceData.actionCandidates.length > 0 ? "fallback" : "openrouter",
      model,
      status: normalized ? "success" : sourceData.actionCandidates.length > 0 ? "fallback" : "success",
      error: null,
    };
  } catch (error) {
    const fallback = buildFallbackSummary(sourceData);
    logActionCandidatesDebug(workspaceId, userId, sourceData, "result", "fallback", "fallback");
    return {
      summaryMarkdown: fallback,
      sourceData,
      provider: "fallback",
      model: null,
      status: "fallback",
      error: String(error),
    };
  }
}

async function upsertSummary(
  supabase: ReturnType<typeof createClient>,
  workspaceId: string,
  userId: string,
  summaryDate: string,
  timeZone: string,
  summary: {
    summaryMarkdown: string;
    sourceData: SourceData;
    provider: string;
    model: string | null;
    status: string;
    error: string | null;
  },
) {
  const payload = {
    workspace_id: workspaceId,
    user_id: userId,
    summary_date: summaryDate,
    timezone: timeZone,
    summary_markdown: summary.summaryMarkdown,
    source_data: summary.sourceData,
    provider: summary.provider,
    model: summary.model,
    prompt_version: PROMPT_VERSION,
    status: summary.status,
    error: summary.error,
  };

  const { error } = await supabase
    .from("daily_ai_summaries")
    .upsert(payload, { onConflict: "workspace_id,user_id,summary_date" });

  if (error) {
    throw new Error(`Failed to upsert summary: ${error.message}`);
  }
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = getEnv("SUPABASE_URL");
    const supabaseAnonKey = getEnv("SUPABASE_ANON_KEY");
    const serviceRoleKey = getEnv("SUPABASE_SERVICE_ROLE_KEY");

    const authHeader = req.headers.get("authorization") || "";
    const token = authHeader.replace("Bearer ", "");
    const isServiceRole = token && token === serviceRoleKey;

    const supabaseService = createClient(supabaseUrl, serviceRoleKey);

    if (!isServiceRole) {
      // Manual request - verify user
      if (!authHeader) {
        return new Response(
          JSON.stringify({ error: "Missing authorization header" }),
          { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      const supabaseUser = createClient(supabaseUrl, supabaseAnonKey, {
        global: { headers: { Authorization: authHeader } },
      });

      const { data: { user }, error: authError } = await supabaseUser.auth.getUser();
      if (authError || !user) {
        return new Response(
          JSON.stringify({ error: "Invalid or expired authentication token" }),
          { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      const body = (await req.json()) as SummaryRequest;
      if (!body?.workspace_id || !body?.user_id) {
        return new Response(
          JSON.stringify({ error: "Missing required fields: workspace_id, user_id" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      if (body.user_id !== user.id) {
        return new Response(
          JSON.stringify({ error: "User mismatch" }),
          { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      const { data: userRow } = await supabaseService
        .from("users")
        .select("timezone")
        .eq("id", body.user_id)
        .maybeSingle();

      const timeZone = (userRow?.timezone as string) || "UTC";
      const summaryDate = body.date || dateToYmdInTz(new Date(), timeZone);

      const { data: existing } = await supabaseService
        .from("daily_ai_summaries")
        .select("id")
        .eq("workspace_id", body.workspace_id)
        .eq("user_id", body.user_id)
        .eq("summary_date", summaryDate)
        .maybeSingle();

      if (existing && !body.force) {
        return new Response(
          JSON.stringify({ status: "exists" }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      const summary = await generateSummary(
        supabaseService,
        body.workspace_id,
        body.user_id,
        timeZone,
        summaryDate,
      );

      await upsertSummary(
        supabaseService,
        body.workspace_id,
        body.user_id,
        summaryDate,
        timeZone,
        summary,
      );

      return new Response(
        JSON.stringify({ status: "ok" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Scheduled mode
    const { data: users } = await supabaseService
      .from("users")
      .select("id,active_workspace_id,timezone")
      .not("active_workspace_id", "is", null);

    const now = new Date();
    const results: Array<{ userId: string; status: string }> = [];

    for (const user of users || []) {
      const timeZone = user.timezone || "UTC";
      const parts = getDatePartsInTimeZone(now, timeZone);

      if (parts.hour !== 6) {
        continue;
      }

      const summaryDate = ymdFromParts(parts);
      const workspaceId = user.active_workspace_id as string;

      const { data: existing } = await supabaseService
        .from("daily_ai_summaries")
        .select("id")
        .eq("workspace_id", workspaceId)
        .eq("user_id", user.id)
        .eq("summary_date", summaryDate)
        .maybeSingle();

      if (existing) {
        results.push({ userId: user.id, status: "exists" });
        continue;
      }

      const summary = await generateSummary(
        supabaseService,
        workspaceId,
        user.id,
        timeZone,
        summaryDate,
      );

      await upsertSummary(
        supabaseService,
        workspaceId,
        user.id,
        summaryDate,
        timeZone,
        summary,
      );

      results.push({ userId: user.id, status: summary.status });
    }

    return new Response(
      JSON.stringify({ status: "ok", processed: results.length }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Daily AI summary error:", error);
    return new Response(
      JSON.stringify({ error: error.message || String(error) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
