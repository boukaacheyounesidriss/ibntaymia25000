/** Groups sidebar pages into clear sections so phone users find things fast. */
export type NavGroupId = "home" | "daily" | "legal" | "pedagogy" | "students" | "system" | "account";

export const NAV_GROUPS: { id: NavGroupId; label: string }[] = [
  { id: "home", label: "الرئيسية" },
  { id: "daily", label: "الميدان اليومي" },
  { id: "legal", label: "الانضباط والمسار القانوني" },
  { id: "pedagogy", label: "الأساتذة والتوقيت" },
  { id: "students", label: "التلاميذ والأنشطة" },
  { id: "system", label: "الإدارة والنظام" },
  { id: "account", label: "حسابي" },
];

const MAP: Record<string, NavGroupId> = {
  "/dashboard": "home", "/dashboard/inbox": "home", "/dashboard/admin": "home", "/dashboard/director": "home",
  "/dashboard/supervisor": "home", "/dashboard/teacher": "home", "/dashboard/parent": "home",
  "/dashboard/student": "home", "/dashboard/gate": "home", "/dashboard/today": "home", "/dashboard/calendar": "home",
  "/dashboard/my-attendance": "home",
  "/dashboard/attendance": "daily", "/dashboard/scan": "daily", "/dashboard/class-rep-attendance": "daily",
  "/dashboard/absence-report": "daily", "/dashboard/sms-alert": "daily", "/dashboard/entry-permits": "daily",
  "/dashboard/parent-phones": "daily", "/dashboard/gate-log": "daily", "/dashboard/weekly": "daily",
  "/dashboard/notifications": "daily",
  "/dashboard/legal-notices": "legal", "/dashboard/decisions": "legal", "/dashboard/behavior": "legal",
  "/dashboard/teachers": "pedagogy", "/dashboard/schedule": "pedagogy", "/dashboard/free-periods": "pedagogy",
  "/dashboard/substitutions": "pedagogy", "/dashboard/exams": "pedagogy", "/dashboard/meetings": "pedagogy",
  "/dashboard/class-reps": "pedagogy",
  "/dashboard/students": "students", "/dashboard/cards": "students", "/dashboard/cards/print": "students",
  "/dashboard/guidance": "students", "/dashboard/library": "students", "/dashboard/trips": "students",
  "/dashboard/reports": "students",
  "/dashboard/import": "system", "/dashboard/users": "system", "/dashboard/permissions": "system",
  "/dashboard/data": "system", "/dashboard/console": "system", "/dashboard/diagnostics": "system",
  "/dashboard/settings": "system",
  "/dashboard/me": "account", "/dashboard/profile": "account", "/dashboard/help": "account", "/dashboard/appearance": "account", "/dashboard/offline": "account",
};

export function groupFor(url: string): NavGroupId {
  return MAP[url] ?? "home";
}
