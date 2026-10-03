/**
 * Streaming a file off disk as a web ReadableStream.
 *
 * Shared by the audio archive and the voice clips: both serve whole files and byte ranges,
 * and both are read by an <audio> element, so both need the same cancel handling — a
 * seek abandons the previous response, and without destroying the node stream the read
 * would run to completion against a client that stopped listening.
 */
import fs from "node:fs";

import { parseRange } from "@/lib/range";

export function streamOf(file: string, start?: number, end?: number): ReadableStream<Uint8Array> {
  const node = fs.createReadStream(file, { start, end });
  return new ReadableStream({
    start(controller) {
      node.on("data", (chunk) => controller.enqueue(new Uint8Array(chunk as Buffer)));
      node.on("end", () => controller.close());
      node.on("error", (error) => controller.error(error));
    },
    cancel() {
      node.destroy();
    },
  });
}

/**
 * A file on disk as the answer to a request an <audio> element made: a 304 when the tag still
 * matches, a 416 for a range past the end, and otherwise the whole file or the range asked for.
 *
 * Range is not optional even for small files: Safari opens audio with `bytes=0-1` and refuses
 * a resource that answers 200, and without it the scrubber cannot seek.
 */
export function serveFile(
  request: Request,
  file: string,
  size: number,
  {
    etag,
    cacheControl,
    headers: extra = {},
    revalidate = true,
    contentType = "audio/mpeg",
  }: {
    etag: string;
    cacheControl: string;
    contentType?: string;
    headers?: Record<string, string>;
    /** False for a URL whose bytes never change, where a conditional request is never sent. */
    revalidate?: boolean;
  },
): Response {
  if (revalidate && request.headers.get("if-none-match") === etag) {
    return new Response(null, { status: 304, headers: { ETag: etag, "Cache-Control": cacheControl } });
  }

  const range = parseRange(request.headers.get("range"), size);
  if (range === "unsatisfiable") {
    return new Response(null, {
      status: 416,
      headers: { "Content-Range": `bytes */${size}`, "Accept-Ranges": "bytes" },
    });
  }

  const headers: Record<string, string> = {
    "Content-Type": contentType,
    "Accept-Ranges": "bytes",
    "Cache-Control": cacheControl,
    ETag: etag,
    ...extra,
  };
  if (!range) {
    headers["Content-Length"] = String(size);
    return new Response(streamOf(file), { status: 200, headers });
  }
  headers["Content-Length"] = String(range.end - range.start + 1);
  headers["Content-Range"] = `bytes ${range.start}-${range.end}/${size}`;
  return new Response(streamOf(file, range.start, range.end), { status: 206, headers });
}
