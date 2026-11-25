import { describe, expect, it } from "vitest";
import { lessonMime, ownsAttachment, readAttachments } from "./lesson-files";
describe("lesson file access", () => {
  it("rejects another teacher's file", () => {
    expect(ownsAttachment("teacher-a/post-a/scan.jpg", "teacher-b", "post-a")).toBe(false);
    expect(ownsAttachment("teacher-a/post-a/scan.jpg", "teacher-a", "post-a")).toBe(true);
  });
  it("rejects attachments from another post or traversal", () => {
    expect(ownsAttachment("teacher-a/post-b/scan.jpg", "teacher-a", "post-a")).toBe(false);
    expect(ownsAttachment("teacher-a/post-a/../scan.jpg", "teacher-a", "post-a")).toBe(false);
  });
  it("accepts lesson documents and photos but not executable web files", () => {
    expect(lessonMime("lesson.PDF")).toBe("application/pdf");
    expect(lessonMime("scan.JPG")).toBe("image/jpeg");
    expect(lessonMime("script.html")).toBeNull();
    expect(lessonMime("script.svg")).toBeNull();
  });
  it("discards invalid attachment payloads", () => {
    expect(readAttachments([{path: "a/b/../x", name: "x", size: 42, type: "image/jpeg"}])).toEqual([]);
    expect(readAttachments(null)).toEqual([]);
  });
});
