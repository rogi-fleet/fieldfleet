import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.43.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type Operation = "risk_score" | "schedule_optimize" | "weekly_digest";

interface CopilotRequest {
  operation: Operation;
  workspace_id: string;
  user_id: string;
  project_id?: string;
  force?: boolean;
  context?: Record<string, unknown>;
}

interface RiskDriver {
  key: string;
  label: string;
  severity: number;
  detail: string;
}

interface ScheduleChange {
  task_id: string;
  add_predecessor_id?: string;
}

interface ScheduleSuggestion {
  id: string;
  title: string;
  impact_summary: string;
  estimated_days_saved: number;
  risk_notes: string[];
  changes: ScheduleChange[];
}

interface WeeklyDigestItem {
  title: string;
  detail: string;
  href?: string;
  badge?: string;
}

interface WeeklyDigestMetrics {
  total_tasks: number;
  incomplete_tasks: number;
  overdue_tasks: number;
  stuck_tasks: number;
  due_soon_tasks: number;
  unassigned_open_tasks: number;
  stale_tasks: number;
  high_priority_open_tasks: number;
}

function getEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing environment variable: ${name}`);
  }
  return value;
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function ymd(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function getWeekBoundsInUtc(from = new Date()) {
  const date = new Date(Date.UTC(from.getUTCFullYear(), from.getUTCMonth(), from.getUTCDate()));
  const day = date.getUTCDay();
  const distanceToMonday = (day + 6) % 7;
  date.setUTCDate(date.getUTCDate() - distanceToMonday);
  const start = new Date(date);
  const end = new Date(date);
  end.setUTCDate(end.getUTCDate() + 6);
  return { weekStart: ymd(start), weekEnd: ymd(end) };
}

function parseDate(value: unknown): Date | null {
  if (typeof value !== "string" || !value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function daysBetween(date: Date, other: Date): number {
  return Math.ceil((other.getTime() - date.getTime()) / (1000 * 60 * 60 * 24));
}

function safeNumber(value: unknown): number {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim()) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}

function buildTaskHref(projectId: string, taskId: unknown): string {
  return `/projects/${projectId}?tab=tasks&taskId=${String(taskId)}`;
}

function buildProjectTasksHref(projectId: string): string {
  return `/projects/${projectId}?tab=tasks`;
}

function buildProjectHref(projectId: string): string {
  return `/projects/${projectId}`;
}

function metricValue(metrics: unknown, key: string): number {
  if (!metrics || typeof metrics !== "object") return 0;
  return safeNumber((metrics as Record<string, unknown>)[key]);
}

function deltaLabel(current: number, previous: number, noun: string): string {
  const delta = current - previous;
  if (delta === 0) {
    return `${noun} unchanged week over week`;
  }
  const direction = delta > 0 ? "up" : "down";
  return `${noun} ${direction} ${Math.abs(delta)} week over week`;
}

function taskPriorityRank(priority: unknown): number {
  switch (String(priority || "").toLowerCase()) {
    case "high":
      return 3;
    case "medium":
      return 2;
    case "low":
      return 1;
    default:
      return 0;
  }
}

function buildTaskDetail(
  task: Record<string, unknown>,
  now: Date,
): { detail: string; badge: string } {
  const parts: string[] = [];
  let badge = "Open";

  const due = parseDate(task.due_date);
  if (String(task.status || "") === "stuck") {
    badge = "Stuck";
    parts.push("Marked stuck");
  }

  if (due) {
    const delta = daysBetween(now, due);
    if (due < now) {
      badge = badge === "Stuck" ? badge : "Overdue";
      parts.push(`Overdue by ${Math.abs(delta)}d`);
    } else if (delta <= 7) {
      if (badge === "Open") badge = "Due soon";
      parts.push(`Due in ${delta}d`);
    } else {
      parts.push(`Due ${ymd(due)}`);
    }
  }

  if (taskPriorityRank(task.priority) >= 3) {
    parts.push("High priority");
  }

  const assignees = Array.isArray(task.assigned_to_ids) ? task.assigned_to_ids : [];
  if (assignees.length === 0) {
    if (badge === "Open") badge = "Unassigned";
    parts.push("Needs owner");
  }

  const updatedAt = parseDate(task.updated_at);
  if (updatedAt) {
    const idleDays = Math.max(0, Math.floor((now.getTime() - updatedAt.getTime()) / (1000 * 60 * 60 * 24)));
    if (idleDays >= 7) {
      parts.push(`No updates ${idleDays}d`);
      if (badge === "Open") badge = "Stale";
    }
  }

  if (parts.length === 0) {
    parts.push("Open task");
  }

  return { detail: parts.join(" • "), badge };
}

function taskUrgencyScore(task: Record<string, unknown>, now: Date): number {
  let score = 0;

  if (String(task.status || "") === "stuck") {
    score += 90;
  }

  const due = parseDate(task.due_date);
  if (due) {
    const delta = daysBetween(now, due);
    if (due < now) {
      score += 120 + Math.abs(delta) * 4;
    } else if (delta <= 7) {
      score += 50 + Math.max(0, 7 - delta) * 3;
    }
  }

  score += taskPriorityRank(task.priority) * 12;

  const assignees = Array.isArray(task.assigned_to_ids) ? task.assigned_to_ids : [];
  if (assignees.length === 0) {
    score += 18;
  }

  const updatedAt = parseDate(task.updated_at);
  if (updatedAt) {
    const idleDays = Math.max(0, Math.floor((now.getTime() - updatedAt.getTime()) / (1000 * 60 * 60 * 24)));
    if (idleDays >= 7) {
      score += Math.min(25, idleDays);
    }
  }

  return score;
}

function buildTaskItem(
  projectId: string,
  task: Record<string, unknown>,
  now: Date,
): WeeklyDigestItem {
  const { detail, badge } = buildTaskDetail(task, now);
  return {
    title: String(task.title || "Untitled task"),
    detail,
    href: buildTaskHref(projectId, task.id),
    badge,
  };
}

function buildWeeklyMetrics(tasks: Array<Record<string, unknown>>, now = new Date()): WeeklyDigestMetrics {
  const counts = getTaskStatusCounts(tasks);
  const incomplete = tasks.filter((task) => task.is_complete !== true);
  const staleTasks = incomplete.filter((task) => {
    const updatedAt = parseDate(task.updated_at);
    if (!updatedAt) return false;
    return Math.floor((now.getTime() - updatedAt.getTime()) / (1000 * 60 * 60 * 24)) >= 7;
  }).length;
  const unassignedOpenTasks = incomplete.filter((task) => {
    const assignees = Array.isArray(task.assigned_to_ids) ? task.assigned_to_ids : [];
    return assignees.length === 0;
  }).length;
  const highPriorityOpenTasks = incomplete.filter((task) => taskPriorityRank(task.priority) >= 3).length;

  return {
    total_tasks: tasks.length,
    incomplete_tasks: incomplete.length,
    overdue_tasks: counts.overdue,
    stuck_tasks: counts.stuck,
    due_soon_tasks: counts.dueSoon,
    unassigned_open_tasks: unassignedOpenTasks,
    stale_tasks: staleTasks,
    high_priority_open_tasks: highPriorityOpenTasks,
  };
}

async function ensureMembership(
  supabaseService: ReturnType<typeof createClient>,
  workspaceId: string,
  userId: string,
) {
  const { data, error } = await supabaseService
    .from("workspace_members")
    .select("workspace_id")
    .eq("workspace_id", workspaceId)
    .eq("user_id", userId)
    .maybeSingle();
  if (error) {
    throw new Error(`Membership check failed: ${error.message}`);
  }
  if (!data) {
    throw new Error("User is not a member of this workspace");
  }
}

async function getFeatureFlags(
  supabaseService: ReturnType<typeof createClient>,
  workspaceId: string,
) {
  const { data } = await supabaseService
    .from("workspace_feature_flags")
    .select("flags")
    .eq("workspace_id", workspaceId)
    .maybeSingle();
  return (data?.flags || {}) as Record<string, boolean>;
}

function requiredFlag(operation: Operation): string {
  switch (operation) {
    case "risk_score":
      return "ai_copilot_risk_v1";
    case "schedule_optimize":
      return "ai_copilot_schedule_v1";
    case "weekly_digest":
      return "ai_copilot_weekly_digest_v1";
  }
}

function getTaskStatusCounts(tasks: Array<Record<string, unknown>>) {
  let overdue = 0;
  let stuck = 0;
  let dueSoon = 0;
  const now = new Date();
  const soon = new Date(now);
  soon.setDate(soon.getDate() + 7);

  for (const task of tasks) {
    const isComplete = task.is_complete === true;
    if (isComplete) continue;

    if (String(task.status || "") === "stuck") {
      stuck += 1;
    }

    const due = parseDate(task.due_date);
    if (!due) continue;
    if (due < now) overdue += 1;
    if (due >= now && due <= soon) dueSoon += 1;
  }

  return { overdue, stuck, dueSoon };
}

function computeRisk(
  project: Record<string, unknown>,
  tasks: Array<Record<string, unknown>>,
) {
  const metrics = buildWeeklyMetrics(tasks);
  const incomplete = metrics.incomplete_tasks;
  const total = tasks.length;
  const overdueRatio = incomplete > 0 ? metrics.overdue_tasks / incomplete : 0;
  const stuckRatio = incomplete > 0 ? metrics.stuck_tasks / incomplete : 0;
  const completionRatio = total > 0 ? (total - incomplete) / total : 0;

  const target = parseDate(project.target_completion_date);
  const now = new Date();
  let schedulePressure = 0;
  if (target) {
    const daysToTarget = Math.ceil((target.getTime() - now.getTime()) / (1000 * 60 * 60 * 24));
    if (daysToTarget <= 14) schedulePressure = 0.22;
    else if (daysToTarget <= 30) schedulePressure = 0.12;
  }

  const scoreRaw =
    overdueRatio * 55 +
    stuckRatio * 28 +
    (1 - completionRatio) * 12 +
    schedulePressure * 100;
  const score = clamp(Math.round(scoreRaw), 0, 100);

  const drivers: RiskDriver[] = [];
  if (metrics.overdue_tasks > 0) {
    drivers.push({
      key: "overdue_tasks",
      label: "Overdue tasks",
      severity: clamp(60 + metrics.overdue_tasks * 6, 0, 100),
      detail: `${metrics.overdue_tasks} task(s) are overdue.`,
    });
  }
  if (metrics.stuck_tasks > 0) {
    drivers.push({
      key: "stuck_tasks",
      label: "Stuck tasks",
      severity: clamp(58 + metrics.stuck_tasks * 8, 0, 100),
      detail: `${metrics.stuck_tasks} task(s) are marked stuck.`,
    });
  }
  if (metrics.due_soon_tasks > 0) {
    drivers.push({
      key: "due_soon",
      label: "Upcoming deadlines",
      severity: clamp(45 + metrics.due_soon_tasks * 4, 0, 100),
      detail: `${metrics.due_soon_tasks} task(s) are due in the next 7 days.`,
    });
  }

  const riskLevel =
    score >= 75 ? "critical" : score >= 50 ? "high" : score >= 30 ? "medium" : "low";

  const recommendedActions = [];
  if (metrics.overdue_tasks > 0) {
    recommendedActions.push("Reschedule or close overdue tasks first.");
  }
  if (metrics.stuck_tasks > 0) {
    recommendedActions.push("Unblock stuck tasks by assigning clear owners.");
  }
  if (metrics.due_soon_tasks > 0) {
    recommendedActions.push("Review due-soon tasks and pull blockers forward.");
  }
  if (metrics.unassigned_open_tasks > 0) {
    recommendedActions.push("Assign owners to unassigned open tasks.");
  }
  if (recommendedActions.length === 0) {
    recommendedActions.push("Maintain current plan and monitor task flow.");
  }

  return {
    project_id: project.id,
    project_name: String(project.name || "Project"),
    risk_score: score,
    risk_level: riskLevel,
    confidence: 0.72,
    drivers: drivers.slice(0, 5),
    recommended_actions: recommendedActions.slice(0, 4),
    metrics,
  };
}

function buildScheduleSuggestions(tasks: Array<Record<string, unknown>>) {
  const suggestions: ScheduleSuggestion[] = [];
  const incomplete = tasks.filter((t) => t.is_complete !== true);
  const withoutPredecessors = incomplete.filter((t) => {
    const predecessors = (t.predecessor_ids || []) as string[];
    return predecessors.length === 0;
  });
  const stuck = incomplete.filter((t) => String(t.status || "") === "stuck");
  const overdue = incomplete.filter((t) => {
    const due = parseDate(t.due_date);
    return !!due && due < new Date();
  });

  if (stuck.length > 0 && overdue.length > 0) {
    const stuckTask = stuck[0];
    const overdueTask = overdue[0];
    if (stuckTask.id !== overdueTask.id) {
      suggestions.push({
        id: "seq-stuck-overdue",
        title: "Sequence stuck work behind overdue critical task",
        impact_summary:
          "Reduce context switching and unblock handoffs by enforcing one critical path item first.",
        estimated_days_saved: 2,
        risk_notes: [
          "May delay non-critical stuck work by 1-2 days.",
          "Requires assignee alignment before applying.",
        ],
        changes: [
          {
            task_id: String(stuckTask.id),
            add_predecessor_id: String(overdueTask.id),
          },
        ],
      });
    }
  }

  if (withoutPredecessors.length >= 2) {
    const first = withoutPredecessors[0];
    const second = withoutPredecessors[1];
    if (first.id !== second.id) {
      suggestions.push({
        id: "order-free-floating",
        title: "Add ordering between free-floating tasks",
        impact_summary:
          "Creates clearer execution order to prevent parallel bottlenecks from ad-hoc sequencing.",
        estimated_days_saved: 1,
        risk_notes: [
          "Low confidence: recommendation is heuristic.",
        ],
        changes: [
          {
            task_id: String(second.id),
            add_predecessor_id: String(first.id),
          },
        ],
      });
    }
  }

  if (suggestions.length === 0) {
    suggestions.push({
      id: "no-op",
      title: "No structural dependency changes recommended",
      impact_summary: "Current dependency graph does not show obvious optimization opportunities.",
      estimated_days_saved: 0,
      risk_notes: ["Re-run after new tasks are added or statuses change."],
      changes: [],
    });
  }

  return {
    suggestion_count: suggestions.length,
    suggestions,
  };
}

function buildWeeklyDigestMarkdown(
  projectName: string,
  risk: ReturnType<typeof computeRisk>,
  summaryLine: string,
  trendLine: string,
  focusLine: string,
  urgentItem?: WeeklyDigestItem,
) {
  const lines = [
    `- **${projectName}** weekly digest`,
    `- Risk level: **${String(risk.risk_level).toUpperCase()}** (${risk.risk_score}/100)`,
    `- ${summaryLine}`,
    `- ${trendLine}`,
    `- Focus this week: ${focusLine}`,
  ];
  if (urgentItem?.href) {
    lines.push(`- Immediate attention: [${urgentItem.title}](${urgentItem.href})`);
  }
  return lines.join("\n");
}

function buildWeeklyDigestReport(
  project: Record<string, unknown>,
  projectId: string,
  weekStart: string,
  tasks: Array<Record<string, unknown>>,
  risk: ReturnType<typeof computeRisk>,
  previousDigestSource?: Record<string, unknown>,
) {
  const now = new Date();
  const metrics = risk.metrics as WeeklyDigestMetrics;
  const previousRisk = previousDigestSource?.risk as Record<string, unknown> | undefined;
  const previousMetrics = previousRisk?.metrics as Record<string, unknown> | undefined;
  const previousRiskScore = safeNumber(previousRisk?.risk_score);
  const hasPrevious = previousDigestSource !== undefined;

  const incompleteTasks = tasks.filter((task) => task.is_complete !== true);
  const urgentTasks = [...incompleteTasks]
    .sort((a, b) => taskUrgencyScore(b, now) - taskUrgencyScore(a, now))
    .slice(0, 3);
  const riskItems = urgentTasks.map((task) => buildTaskItem(projectId, task, now));

  const dueSoonTasks = incompleteTasks
    .filter((task) => {
      const due = parseDate(task.due_date);
      if (!due || due < now) return false;
      return daysBetween(now, due) <= 7;
    })
    .sort((a, b) => taskUrgencyScore(b, now) - taskUrgencyScore(a, now));

  const staleTasks = incompleteTasks
    .filter((task) => {
      const updatedAt = parseDate(task.updated_at);
      if (!updatedAt) return false;
      return Math.floor((now.getTime() - updatedAt.getTime()) / (1000 * 60 * 60 * 24)) >= 7;
    })
    .sort((a, b) => taskUrgencyScore(b, now) - taskUrgencyScore(a, now));

  const watchItems: WeeklyDigestItem[] = [];
  const seenWatch = new Set<string>();
  for (const task of [...dueSoonTasks, ...staleTasks]) {
    const key = String(task.id || "");
    if (!key || seenWatch.has(key)) continue;
    seenWatch.add(key);
    watchItems.push(buildTaskItem(projectId, task, now));
    if (watchItems.length >= 3) break;
  }

  const projectTasksHref = buildProjectTasksHref(projectId);
  const priorityItems: WeeklyDigestItem[] = [];
  if (metrics.overdue_tasks > 0) {
    priorityItems.push({
      title: `Triage ${metrics.overdue_tasks} overdue task(s)`,
      detail: "Close, reschedule, or explicitly re-sequence late work before adding new tasks.",
      href: riskItems[0]?.href || projectTasksHref,
      badge: "Now",
    });
  }
  if (metrics.stuck_tasks > 0) {
    const stuckTask = incompleteTasks.find((task) => String(task.status || "") === "stuck");
    priorityItems.push({
      title: `Unblock ${metrics.stuck_tasks} stuck task(s)`,
      detail: "Resolve owners, dependencies, or missing decisions on blocked work.",
      href: stuckTask ? buildTaskHref(projectId, stuckTask.id) : projectTasksHref,
      badge: "Blocker",
    });
  }
  if (metrics.unassigned_open_tasks > 0) {
    const unassignedTask = incompleteTasks.find((task) => {
      const assignees = Array.isArray(task.assigned_to_ids) ? task.assigned_to_ids : [];
      return assignees.length === 0;
    });
    priorityItems.push({
      title: `Assign owners to ${metrics.unassigned_open_tasks} open task(s)`,
      detail: "Unassigned work is likely to slip because no single person owns the next move.",
      href: unassignedTask ? buildTaskHref(projectId, unassignedTask.id) : projectTasksHref,
      badge: "Owner",
    });
  }
  if (metrics.due_soon_tasks > 0) {
    priorityItems.push({
      title: `Confirm the next 7 days of deadlines`,
      detail: `${metrics.due_soon_tasks} task(s) are due soon; verify sequencing and owner readiness now.`,
      href: watchItems[0]?.href || projectTasksHref,
      badge: "Soon",
    });
  }
  if (priorityItems.length === 0) {
    priorityItems.push({
      title: "Keep the current plan moving",
      detail: "No obvious blockers surfaced this week; monitor the task queue and preserve momentum.",
      href: projectTasksHref,
      badge: "Stable",
    });
  }

  const highlights: WeeklyDigestItem[] = [];
  if (hasPrevious) {
    const riskDelta = risk.risk_score - previousRiskScore;
    if (riskDelta <= -5) {
      highlights.push({
        title: `Risk improved by ${Math.abs(riskDelta)} point(s)`,
        detail: `${previousRiskScore} -> ${risk.risk_score} since last week's digest.`,
        href: buildProjectHref(projectId),
        badge: "Improving",
      });
    } else if (riskDelta >= 5) {
      highlights.push({
        title: `Risk climbed by ${riskDelta} point(s)`,
        detail: `${previousRiskScore} -> ${risk.risk_score} week over week.`,
        href: buildProjectHref(projectId),
        badge: "Rising",
      });
    }

    const overdueDetail = deltaLabel(
      metrics.overdue_tasks,
      metricValue(previousMetrics, "overdue_tasks"),
      "Overdue tasks",
    );
    highlights.push({
      title: "Week-over-week task pressure",
      detail: overdueDetail,
      href: projectTasksHref,
      badge: "Trend",
    });

    const stuckPrevious = metricValue(previousMetrics, "stuck_tasks");
    if (metrics.stuck_tasks !== stuckPrevious) {
      highlights.push({
        title: "Blocked work changed",
        detail: deltaLabel(metrics.stuck_tasks, stuckPrevious, "Stuck tasks"),
        href: projectTasksHref,
        badge: "Trend",
      });
    }
  } else {
    const completeCount = Math.max(0, metrics.total_tasks - metrics.incomplete_tasks);
    highlights.push({
      title: `${completeCount} of ${metrics.total_tasks} task(s) complete`,
      detail: `${metrics.incomplete_tasks} open task(s) remain in the current project queue.`,
      href: projectTasksHref,
      badge: "Snapshot",
    });
  }

  if (metrics.overdue_tasks === 0 && metrics.stuck_tasks === 0) {
    highlights.push({
      title: "No overdue or stuck work right now",
      detail: "Execution pressure is coming from upcoming deadlines rather than slipped work.",
      href: projectTasksHref,
      badge: "Clean",
    });
  } else if (metrics.high_priority_open_tasks > 0) {
    highlights.push({
      title: `${metrics.high_priority_open_tasks} high-priority task(s) still open`,
      detail: "High-priority work should stay visible in the next planning pass.",
      href: projectTasksHref,
      badge: "Priority",
    });
  }

  const summaryLine =
    `${Math.max(0, metrics.total_tasks - metrics.incomplete_tasks)} of ${metrics.total_tasks} task(s) are complete; ` +
    `${metrics.overdue_tasks} overdue, ${metrics.stuck_tasks} stuck, and ${metrics.due_soon_tasks} due in the next 7 days.`;

  let trendLine = "This is the first saved weekly snapshot for trend tracking.";
  if (hasPrevious) {
    const fragments: string[] = [];
    const riskDelta = risk.risk_score - previousRiskScore;
    if (riskDelta !== 0) {
      fragments.push(`risk ${riskDelta > 0 ? "up" : "down"} ${Math.abs(riskDelta)}`);
    }
    const overdueDelta = metrics.overdue_tasks - metricValue(previousMetrics, "overdue_tasks");
    if (overdueDelta !== 0) {
      fragments.push(`overdue ${overdueDelta > 0 ? "up" : "down"} ${Math.abs(overdueDelta)}`);
    }
    const stuckDelta = metrics.stuck_tasks - metricValue(previousMetrics, "stuck_tasks");
    if (stuckDelta !== 0) {
      fragments.push(`stuck ${stuckDelta > 0 ? "up" : "down"} ${Math.abs(stuckDelta)}`);
    }
    trendLine = fragments.length > 0
      ? `Week over week: ${fragments.join(", ")}.`
      : "Week over week: no material change in tracked task pressure.";
  }

  const focusLine = priorityItems.slice(0, 2).map((item) => item.title.toLowerCase()).join("; ");
  const digestMarkdown = buildWeeklyDigestMarkdown(
    String(project.name || "Project"),
    risk,
    summaryLine,
    trendLine,
    focusLine,
    riskItems[0],
  );

  return {
    digest_markdown: digestMarkdown,
    overview: summaryLine,
    highlights: highlights.slice(0, 4).map((item) => item.detail),
    risks: riskItems.slice(0, 3).map((item) => `${item.title}: ${item.detail}`),
    next_week_priorities: priorityItems.slice(0, 4).map((item) => item.title),
    highlight_items: highlights.slice(0, 4),
    risk_items: riskItems.slice(0, 3),
    priority_items: priorityItems.slice(0, 4),
    watch_items: watchItems.slice(0, 3),
    source_data: {
      week_start_date: weekStart,
      risk,
      metrics,
      previous_week_metrics: previousMetrics || null,
      task_count: tasks.length,
    },
  };
}

async function logEvent(
  supabaseService: ReturnType<typeof createClient>,
  payload: Record<string, unknown>,
) {
  const { error } = await supabaseService.from("ai_copilot_events").insert(payload);
  if (error) {
    console.error("Failed to log ai_copilot_events:", error.message);
  }
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const startedAt = Date.now();

  try {
    const supabaseUrl = getEnv("SUPABASE_URL");
    const supabaseAnonKey = getEnv("SUPABASE_ANON_KEY");
    const serviceRoleKey = getEnv("SUPABASE_SERVICE_ROLE_KEY");

    const authHeader = req.headers.get("authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const supabaseUser = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const supabaseService = createClient(supabaseUrl, serviceRoleKey);

    const {
      data: { user },
      error: authError,
    } = await supabaseUser.auth.getUser();
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Invalid or expired authentication token" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const body = (await req.json()) as CopilotRequest;
    if (!body?.workspace_id || !body?.user_id || !body?.operation) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: workspace_id, user_id, operation" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    if (body.user_id !== user.id) {
      return new Response(
        JSON.stringify({ error: "User mismatch" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    await ensureMembership(supabaseService, body.workspace_id, body.user_id);

    const flags = await getFeatureFlags(supabaseService, body.workspace_id);
    const flag = requiredFlag(body.operation);
    if (flags[flag] !== true) {
      return new Response(
        JSON.stringify({
          error: "Feature disabled",
          required_flag: flag,
        }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    if (!body.project_id) {
      return new Response(
        JSON.stringify({ error: "project_id is required for this operation" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const { data: project, error: projectError } = await supabaseService
      .from("projects")
      .select("id,name,target_completion_date")
      .eq("workspace_id", body.workspace_id)
      .eq("id", body.project_id)
      .maybeSingle();
    if (projectError || !project) {
      return new Response(
        JSON.stringify({ error: "Project not found" }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const { data: tasks, error: tasksError } = await supabaseService
      .from("tasks")
      .select("id,title,is_complete,status,due_date,predecessor_ids,updated_at,priority,progress,assigned_to_ids")
      .eq("workspace_id", body.workspace_id)
      .eq("project_id", body.project_id);
    if (tasksError) {
      throw new Error(`Failed to fetch tasks: ${tasksError.message}`);
    }

    const risk = computeRisk(project, tasks || []);
    let result: Record<string, unknown>;
    if (body.operation === "risk_score") {
      result = risk;
    } else if (body.operation === "schedule_optimize") {
      result = buildScheduleSuggestions(tasks || []);
    } else {
      const { weekStart, weekEnd } = getWeekBoundsInUtc();
      const { data: previousDigestRow } = await supabaseService
        .from("weekly_ai_project_digests")
        .select("week_start_date,source_data")
        .eq("workspace_id", body.workspace_id)
        .eq("user_id", body.user_id)
        .eq("project_id", body.project_id)
        .lt("week_start_date", weekStart)
        .order("week_start_date", { ascending: false })
        .limit(1)
        .maybeSingle();

      const digestReport = buildWeeklyDigestReport(
        project,
        body.project_id,
        weekStart,
        tasks || [],
        risk,
        previousDigestRow?.source_data as Record<string, unknown> | undefined,
      );
      const digest = {
        workspace_id: body.workspace_id,
        user_id: body.user_id,
        project_id: body.project_id,
        week_start_date: weekStart,
        week_end_date: weekEnd,
        timezone: "UTC",
        digest_markdown: digestReport.digest_markdown,
        source_data: digestReport.source_data,
        provider: "rule_based",
        model: null,
        prompt_version: "v2",
        status: "success",
        error: null,
        generated_at: new Date().toISOString(),
      };

      if (body.force) {
        await supabaseService
          .from("weekly_ai_project_digests")
          .delete()
          .eq("workspace_id", body.workspace_id)
          .eq("user_id", body.user_id)
          .eq("project_id", body.project_id)
          .eq("week_start_date", weekStart);
      }

      const { error: digestError } = await supabaseService
        .from("weekly_ai_project_digests")
        .upsert(digest, { onConflict: "workspace_id,user_id,project_id,week_start_date" });
      if (digestError) {
        throw new Error(`Failed to store weekly digest: ${digestError.message}`);
      }

      result = {
        project_id: body.project_id,
        week_start_date: weekStart,
        week_end_date: weekEnd,
        overview: digestReport.overview,
        digest_markdown: digestReport.digest_markdown,
        highlights: digestReport.highlights,
        risks: digestReport.risks,
        next_week_priorities: digestReport.next_week_priorities,
        highlight_items: digestReport.highlight_items,
        risk_items: digestReport.risk_items,
        priority_items: digestReport.priority_items,
        watch_items: digestReport.watch_items,
      };
    }

    const latency = Date.now() - startedAt;
    await logEvent(supabaseService, {
      workspace_id: body.workspace_id,
      user_id: body.user_id,
      project_id: body.project_id,
      operation: body.operation,
      status: "success",
      request_payload: body.context ?? {},
      response_payload: result,
      provider: "rule_based",
      model: null,
      latency_ms: latency,
      error: null,
    });

    return new Response(
      JSON.stringify({
        operation: body.operation,
        result,
        meta: {
          provider: "rule_based",
          model: null,
          prompt_version: "v2",
          latency_ms: latency,
        },
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("ai-copilot error:", error);
    return new Response(
      JSON.stringify({ error: error.message || String(error) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
