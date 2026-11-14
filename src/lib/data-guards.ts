// Raw data editing must not bypass the dedicated enrollment decision flow.
export function guardStudentValues(values: Record<string, unknown>, existing: boolean) {
  const protectedFields = ["enrollment_status", "struck_off_at", "struck_off_by", "struck_off_reason"];
  for (const field of protectedFields) {
    if (!(field in values)) continue;
    if (!existing && field === "enrollment_status" && values[field] === "active") continue;
    throw new Error("حالة التسجيل والشطب تُعدّل من المسار القانوني بقرار المدير، وليس من مستكشف البيانات.");
  }
}