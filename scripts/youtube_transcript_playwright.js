#!/usr/bin/env node

// Playwright-based YouTube transcript extractor for n8n Execute Command node.
// Always prints one JSON object to stdout, including rich error/debug context.

function parseArgs(argv) {
  const out = {};
  for (let i = 2; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith('--')) continue;
    const key = token.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith('--')) {
      out[key] = 'true';
      continue;
    }
    out[key] = next;
    i += 1;
  }
  return out;
}

function decodeHtmlEntities(input) {
  if (!input) return '';
  return input
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)))
    .replace(/&#x([0-9a-fA-F]+);/g, (_, n) => String.fromCharCode(parseInt(n, 16)));
}

function normalizeWhitespace(input) {
  return String(input || '')
    .replace(/\s+/g, ' ')
    .trim();
}

function extractFromTimedTextXml(text) {
  const matches = [...String(text || '').matchAll(/<text[^>]*>([\s\S]*?)<\/text>/g)];
  const lines = matches
    .map((m) => decodeHtmlEntities(m[1]).replace(/<[^>]+>/g, ' '))
    .map((v) => normalizeWhitespace(v))
    .filter(Boolean);
  return lines;
}

function extractFromVtt(text) {
  const lines = String(text || '').split(/\r?\n/);
  const out = [];
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    if (trimmed === 'WEBVTT') continue;
    if (/^\d+$/.test(trimmed)) continue;
    if (/^\d{2}:\d{2}:\d{2}\.\d{3}\s+-->\s+\d{2}:\d{2}:\d{2}\.\d{3}/.test(trimmed)) continue;
    out.push(normalizeWhitespace(decodeHtmlEntities(trimmed.replace(/<[^>]+>/g, ' '))));
  }
  return out.filter(Boolean);
}

function dedupePreserveOrder(lines) {
  const seen = new Set();
  const out = [];
  for (const line of lines) {
    if (!seen.has(line)) {
      seen.add(line);
      out.push(line);
    }
  }
  return out;
}

function formatError(err) {
  return {
    message: String(err && err.message ? err.message : err),
    stack: String(err && err.stack ? err.stack : '')
  };
}

function normalizeCdpUrl(rawUrl) {
  const value = String(rawUrl || '').trim();
  if (!value) return '';

  // Browserless may return a non-tokenized websocket URL when starting from HTTP.
  // If a token is present, prefer ws(s) directly so auth is preserved.
  if (value.startsWith('http://') || value.startsWith('https://')) {
    try {
      const parsed = new URL(value);
      if (parsed.searchParams.has('token')) {
        const wsProtocol = parsed.protocol === 'https:' ? 'wss:' : 'ws:';
        return `${wsProtocol}//${parsed.host}${parsed.pathname}${parsed.search}`;
      }
    } catch (_) {
      // Fall through to raw value.
    }
  }

  return value;
}

let emitted = false;
function emit(payload) {
  if (emitted) return;
  emitted = true;
  process.stdout.write(JSON.stringify(payload));
}

async function clickFirstVisible(page, selectors, debug, stageName) {
  for (const selector of selectors) {
    try {
      const locator = page.locator(selector).first();
      const count = await locator.count();
      if (count < 1) continue;
      const visible = await locator.isVisible({ timeout: 500 });
      if (!visible) continue;
      await locator.click({ timeout: 1500 });
      debug.stages.push(stageName + ':' + selector);
      return true;
    } catch (_) {
      // Continue trying selectors.
    }
  }
  return false;
}

async function run() {
  const startedAt = Date.now();
  const args = parseArgs(process.argv);
  const videoUrl = String(args.videoUrl || '').trim();
  const requestedLanguage = String(args.language || '').trim();
  const cdpUrl = normalizeCdpUrl(
    args.cdpUrl ||
      process.env.PLAYWRIGHT_CDP_URL ||
      'ws://browserless-transcript:3000?token=YOUR_BROWSERLESS_TOKEN'
  );
  const timeoutMs = Number(args.timeoutMs || 45000);

  const debug = {
    stage: 'init',
    stages: [],
    requested_language: requestedLanguage || '',
    cdp_url: cdpUrl ? cdpUrl.slice(0, 300) : '',
    timedtext_hits: 0,
    timedtext_nonempty_hits: 0,
    last_timedtext_url: ''
  };

  if (!videoUrl) {
    return {
      status: 'error',
      transcript_text: '',
      source: 'none',
      language: requestedLanguage || '',
      error: {
        message: 'Missing required --videoUrl argument',
        stack: ''
      },
      debug
    };
  }

  let chromium;
  try {
    ({ chromium } = require('playwright'));
  } catch (err) {
    return {
      status: 'error',
      transcript_text: '',
      source: 'none',
      language: requestedLanguage || '',
      error: formatError(err),
      debug: {
        ...debug,
        stage: 'require_playwright_failed',
        note: 'Install Playwright in runtime environment, example: npm i playwright'
      }
    };
  }

  let browser;
  let context;
  let page;
  const networkLines = [];

  try {
    debug.stage = 'launch_browser';
    if (cdpUrl) {
      browser = await chromium.connectOverCDP(cdpUrl, { timeout: timeoutMs });
      debug.stages.push('browser_connected_over_cdp');

      const existingContexts = browser.contexts();
      if (existingContexts.length > 0) {
        context = existingContexts[0];
      } else {
        context = await browser.newContext({
          locale: 'en-US',
          userAgent:
            'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'
        });
      }
    } else {
      browser = await chromium.launch({
        headless: true,
        args: ['--no-sandbox', '--disable-setuid-sandbox']
      });

      context = await browser.newContext({
        locale: 'en-US',
        userAgent:
          'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'
      });
    }

    page = await context.newPage();

    page.on('response', async (response) => {
      try {
        const url = response.url();
        if (!url.includes('/api/timedtext')) return;

        debug.timedtext_hits += 1;
        debug.last_timedtext_url = url.slice(0, 800);

        const body = await response.text();
        if (!body || !body.trim()) return;

        let lines = [];
        if (body.includes('<text')) {
          lines = extractFromTimedTextXml(body);
        } else {
          lines = extractFromVtt(body);
        }

        if (lines.length > 0) {
          debug.timedtext_nonempty_hits += 1;
          networkLines.push(...lines);
        }
      } catch (_) {
        // Network listener must stay resilient.
      }
    });

    debug.stage = 'goto_video';
    await page.goto(videoUrl, {
      waitUntil: 'domcontentloaded',
      timeout: timeoutMs
    });

    await page.waitForTimeout(1200);

    debug.stage = 'open_description';
    await clickFirstVisible(
      page,
      [
        '#description-inline-expander tp-yt-paper-button#expand',
        'tp-yt-paper-button#expand',
        'ytd-text-inline-expander #expand',
        'ytd-video-secondary-info-renderer #expand'
      ],
      debug,
      'clicked_show_more'
    );

    debug.stage = 'open_transcript';
    const transcriptOpened =
      (await clickFirstVisible(
        page,
        [
          'button[aria-label*="Show transcript"]',
          'button[aria-label*="Transcript"]',
          'ytd-button-renderer button[aria-label*="transcript"]',
          'ytd-menu-service-item-renderer tp-yt-paper-item'
        ],
        debug,
        'clicked_transcript_button'
      )) ||
      (await (async () => {
        try {
          const byRole = page.getByRole('button', { name: /transcript/i }).first();
          if (await byRole.isVisible({ timeout: 1000 })) {
            await byRole.click({ timeout: 1500 });
            debug.stages.push('clicked_transcript_button:getByRole');
            return true;
          }
        } catch (_) {
          // no-op
        }
        return false;
      })());

    debug.transcript_button_clicked = transcriptOpened;

    await page.waitForTimeout(1800);

    debug.stage = 'extract_dom_transcript';
    const domSelectors = [
      'ytd-transcript-segment-renderer .segment-text',
      'ytd-transcript-segment-renderer yt-formatted-string',
      'ytd-transcript-body-renderer ytd-transcript-segment-renderer',
      'ytd-transcript-segment-list-renderer ytd-transcript-segment-renderer'
    ];

    let domLines = [];
    for (const selector of domSelectors) {
      const lines = await page.$$eval(selector, (nodes) =>
        nodes.map((n) => (n.innerText || n.textContent || '').trim()).filter(Boolean)
      ).catch(() => []);
      if (lines.length > 0) {
        debug.stages.push('dom_selector_hit:' + selector);
        domLines = lines;
        break;
      }
    }

    domLines = dedupePreserveOrder(domLines.map(normalizeWhitespace).filter(Boolean));
    const networkNormalized = dedupePreserveOrder(networkLines.map(normalizeWhitespace).filter(Boolean));

    const elapsedMs = Date.now() - startedAt;

    if (domLines.length > 0) {
      return {
        status: 'ok',
        transcript_text: domLines.join('\n'),
        source: 'dom',
        language: requestedLanguage || '',
        error: { message: '', stack: '' },
        debug: {
          ...debug,
          stage: 'done_dom',
          dom_lines: domLines.length,
          network_lines: networkNormalized.length,
          elapsed_ms: elapsedMs
        }
      };
    }

    if (networkNormalized.length > 0) {
      return {
        status: 'ok',
        transcript_text: networkNormalized.join('\n'),
        source: 'network',
        language: requestedLanguage || '',
        error: { message: '', stack: '' },
        debug: {
          ...debug,
          stage: 'done_network',
          dom_lines: 0,
          network_lines: networkNormalized.length,
          elapsed_ms: elapsedMs
        }
      };
    }

    return {
      status: 'unavailable',
      transcript_text: '',
      source: 'none',
      language: requestedLanguage || '',
      error: {
        message: 'Transcript could not be extracted via DOM or network timedtext payloads',
        stack: ''
      },
      debug: {
        ...debug,
        stage: 'no_transcript_found',
        elapsed_ms: elapsedMs
      }
    };
  } catch (err) {
    return {
      status: 'error',
      transcript_text: '',
      source: 'none',
      language: requestedLanguage || '',
      error: formatError(err),
      debug: {
        ...debug,
        stage: 'exception_main',
        elapsed_ms: Date.now() - startedAt
      }
    };
  } finally {
    try {
      if (page) await page.close();
    } catch (_) {
      // no-op
    }
    try {
      if (context) await context.close();
    } catch (_) {
      // no-op
    }
    try {
      if (browser) await browser.close();
    } catch (_) {
      // no-op
    }
  }
}

(async () => {
  try {
    const payload = await run();
    emit(payload);
  } catch (outerErr) {
    emit({
      status: 'error',
      transcript_text: '',
      source: 'none',
      language: '',
      error: formatError(outerErr),
      debug: {
        stage: 'exception_outer_scope'
      }
    });
  }
})();

process.on('uncaughtException', (err) => {
  emit({
    status: 'error',
    transcript_text: '',
    source: 'none',
    language: '',
    error: formatError(err),
    debug: {
      stage: 'uncaught_exception_handler'
    }
  });
  process.exitCode = 0;
});

process.on('unhandledRejection', (reason) => {
  emit({
    status: 'error',
    transcript_text: '',
    source: 'none',
    language: '',
    error: formatError(reason),
    debug: {
      stage: 'unhandled_rejection_handler'
    }
  });
  process.exitCode = 0;
});
