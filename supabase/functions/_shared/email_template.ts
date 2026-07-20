export interface TaskFleetEmailOptions {
  preheader?: string;
  title: string;
  intro?: string;
  bodyHtml: string;
  ctaLabel?: string;
  ctaUrl?: string;
  footerHtml?: string;
}

export function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

export function buildTaskFleetEmail(options: TaskFleetEmailOptions): string {
  const preheader = options.preheader?.trim() ?? "";
  const intro = options.intro?.trim();
  const cta =
    options.ctaLabel && options.ctaUrl
      ? `
        <div style="text-align: center; margin: 24px 0;">
          <a href="${options.ctaUrl}" style="display: inline-block; background: #0d4f8b; color: #ffffff; text-decoration: none; padding: 12px 26px; border-radius: 8px; font-weight: 600;">
            ${options.ctaLabel}
          </a>
        </div>
      `
      : "";
  const footer =
    options.footerHtml ??
    "<p style=\"margin: 0;\">FieldFleet</p><p style=\"margin: 8px 0 0 0;\">If this wasn’t expected, you can ignore this email.</p>";

  return `
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <title>${escapeHtml(options.title)}</title>
      </head>
      <body style="margin: 0; padding: 20px; background: #f5f8fc; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; color: #1f2937;">
        ${
          preheader
            ? `<div style="display:none;max-height:0;overflow:hidden;opacity:0;">${escapeHtml(preheader)}</div>`
            : ""
        }
        <div style="max-width: 620px; margin: 0 auto;">
          <div style="background: linear-gradient(140deg, #0a1628 0%, #0d4f8b 70%, #1565a8 100%); color: #ffffff; padding: 26px 28px; border-radius: 12px 12px 0 0;">
            <h1 style="margin: 0; font-size: 24px; line-height: 1.3;">${escapeHtml(options.title)}</h1>
          </div>
          <div style="background: #ffffff; border: 1px solid #dbe4ef; border-top: none; padding: 28px;">
            ${intro ? `<p style="margin: 0 0 12px 0;">${escapeHtml(intro)}</p>` : ""}
            ${options.bodyHtml}
            ${cta}
          </div>
          <div style="background: #eef3f9; color: #516173; font-size: 13px; padding: 18px 24px; border-radius: 0 0 12px 12px; border: 1px solid #dbe4ef; border-top: none;">
            ${footer}
          </div>
        </div>
      </body>
    </html>
  `;
}

