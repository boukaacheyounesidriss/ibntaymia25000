export type LessonAttachment = { path: string; name: string; type: string; size: number };
export const LESSON_BUCKET = "teacher-lessons";
const TYPES: Record<string, string> = {
  jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png", webp: "image/webp", gif: "image/gif", avif: "image/avif", heic: "image/heic", heif: "image/heif",
  pdf: "application/pdf", doc: "application/msword", docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  ppt: "application/vnd.ms-powerpoint", pptx: "application/vnd.openxmlformats-officedocument.presentationml.presentation", odt: "application/vnd.oasis.opendocument.text",
};
export const LESSON_ACCEPT = Object.keys(TYPES).map((s) => `.${s}`).join(",");
export function lessonMime(name: string): string | null {
  return TYPES[name.split(".").pop()?.toLowerCase() ?? ""] ?? null;
}
export function readAttachments(value: unknown): LessonAttachment[] {
  if (!Array.isArray(value)) return [];
  return value.filter((a): a is LessonAttachment => typeof a === "object" && a !== null &&
    typeof a.path === "string" && !a.path.includes("..") && a.path.split("/").length === 3 &&
    typeof a.name === "string" && typeof a.type === "string" && typeof a.size === "number");
}
export function ownsAttachment(path: string, teacherId: string, postId: string): boolean {
  return path.startsWith(`${teacherId}/${postId}/`) && !path.includes("..") && path.split("/").length === 3;
}
export function fileSize(bytes: number): string {
  return bytes < 1024 * 1024 ? `${Math.max(1, Math.round(bytes / 1024))} KB` : `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}
/** Runs only after a user selects a photo. Keep the original if compression fails or grows it. */
export async function prepareLessonFile(file: File, compress: boolean): Promise<File> {
  const type = lessonMime(file.name);
  if (!type) throw new Error(`صيغة غير مدعومة: ${file.name}؛ اختر صورة أو PDF أو ملف Word أو PowerPoint.`);
  const original = file.type === type ? file : new File([file], file.name, { type });
  if (!compress || !["image/jpeg", "image/png", "image/webp"].includes(type)) return original;
  const url = URL.createObjectURL(original);
  try {
    const image = new Image();
    image.src = url;
    await image.decode();
    const scale = Math.min(1, 2200 / Math.max(image.naturalWidth, image.naturalHeight));
    const canvas = document.createElement("canvas");
    canvas.width = Math.round(image.naturalWidth * scale);
    canvas.height = Math.round(image.naturalHeight * scale);
    const ctx = canvas.getContext("2d");
    if (!ctx) return original;
    // Browser default opaque background prevents transparent PNG scans from becoming black.
    ctx.fillStyle = "white";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.drawImage(image, 0, 0, canvas.width, canvas.height);
    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.88));
    if (!blob || blob.size >= original.size) return original;
    return new File([blob], file.name.replace(/\.[^.]+$/, ".jpg"), { type: "image/jpeg" });
  } catch { return original; }
  finally { URL.revokeObjectURL(url); }
}
