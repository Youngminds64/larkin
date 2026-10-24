import type http from "node:http";
import { assertWriteRequest, boundedJson } from "./dashboard-config-controller.js";
import { collectWorkspaceEntry, writeWorkspaceFile } from "./dashboard-view-model.js";

function statusCodeOf(error: unknown): number {
  return typeof error === "object" && error !== null && "statusCode" in error && typeof error.statusCode === "number" ? error.statusCode : 500;
}

function json(res: http.ServerResponse, statusCode: number, body: unknown): void {
  res.writeHead(statusCode, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" });
  res.end(JSON.stringify(body));
}

/** Workspace browsing (GET) and CSRF-protected text-file saves (PUT) for the dashboard server. */
export function createDashboardWorkspaceController({ csrfCapability }: { csrfCapability: string }) {
  return {
    async handle(req: http.IncomingMessage, res: http.ServerResponse, requestUrl: URL): Promise<boolean> {
      if (requestUrl.pathname === "/api/workspace/file" && req.method === "PUT") {
        let body: Record<string, unknown>;
        try {
          assertWriteRequest(req, csrfCapability);
          // JSON escaping can roughly double a 1 MB text file.
          body = await boundedJson(req, 3 * 1024 * 1024);
        } catch {
          json(res, 403, { error: "workspace write rejected" });
          return true;
        }
        try {
          const saved = writeWorkspaceFile(body);
          console.log(`[dashboard] workspace write agent=${String(body.agentId)} path=${String(body.path)} bytes=${Buffer.byteLength(String(body.content))}`);
          json(res, 200, saved);
        } catch (error) {
          json(res, statusCodeOf(error), { error: error instanceof Error ? error.message : String(error) });
        }
        return true;
      }
      if (requestUrl.pathname === "/api/workspace") {
        try { json(res, 200, collectWorkspaceEntry(requestUrl.searchParams.get("agent"), requestUrl.searchParams.get("path") || "")); }
        catch (error) { json(res, statusCodeOf(error), { error: error instanceof Error ? error.message : String(error) }); }
        return true;
      }
      return false;
    },
  };
}
