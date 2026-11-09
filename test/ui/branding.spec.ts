import { readFileSync } from 'node:fs';

import { expect, test, type APIRequestContext, type Page } from '@playwright/test';

const adminKey = process.env.AGW_ADMIN_KEY;

const adminHeaders = () => {
  if (!adminKey) throw new Error('AGW_ADMIN_KEY is required');
  return { 'X-API-KEY': adminKey };
};

const seedResources = async (request: APIRequestContext) => {
  const certPath = process.env.AGW_UI_TEST_CERT;
  const keyPath = process.env.AGW_UI_TEST_KEY;
  if (!certPath || !keyPath) {
    throw new Error('AGW_UI_TEST_CERT and AGW_UI_TEST_KEY are required');
  }

  const routeResponse = await request.put('/apisix/admin/routes/ui-smoke-route', {
    headers: adminHeaders(),
    data: {
      uri: '/ui-smoke',
      upstream: {
        type: 'roundrobin',
        nodes: [{ host: '127.0.0.1', port: 9080, weight: 1 }],
      },
    },
  });
  expect(routeResponse.ok()).toBeTruthy();

  const sslResponse = await request.put('/apisix/admin/ssls/ui-smoke-ssl', {
    headers: adminHeaders(),
    data: {
      cert: readFileSync(certPath, 'utf8'),
      key: readFileSync(keyPath, 'utf8'),
      snis: ['ui-smoke.test'],
      status: 1,
    },
  });
  expect(sslResponse.ok()).toBeTruthy();
};

const authenticate = async (page: Page) => {
  await page.goto('/ui/routes?page=1&page_size=10');
  const dialog = page.locator('[role="dialog"]').filter({ hasText: 'Admin Key' });
  await expect(dialog).toBeVisible();
  await page.getByLabel('Admin Key').fill(adminKey ?? '');
  await page.keyboard.press('Escape');
  await expect(dialog).toBeHidden();
  await page.reload();
  await expect(page.getByRole('heading', { name: 'Routes' })).toBeVisible();
};

test.beforeAll(async ({ request }) => {
  await seedResources(request);
});

test('desktop branding, title, logo, docs, and translation CTA', async ({
  page,
}) => {
  await authenticate(page);

  await expect(page).toHaveTitle('Routes - AGW Dashboard');
  await expect(page.getByText('AGW Dashboard', { exact: true })).toBeVisible();
  await expect(page.locator('link[rel="icon"]')).toHaveCount(0);
  await expect(
    page.locator('img[src*="apisix-logo"], img[alt*="APISIX Logo"]')
  ).toHaveCount(0);
  await expect(
    page.locator('a[href*="apisix.apache.org/docs"]')
  ).toHaveCount(0);
  await expect(page.locator('a[href="/ui/docs/"]').first()).toBeVisible();

  await page.getByRole('button', { name: /Select language/ }).click();
  await expect(
    page.getByText(/Help Us Translate|帮助我们进行翻译/)
  ).toHaveCount(0);
  await expect(page.locator('a[href*="issues/1407"]')).toHaveCount(0);
});

test('mobile header keeps the AGW wordmark', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await authenticate(page);

  await expect(page.getByText('AGW', { exact: true })).toBeVisible();
  await expect(page.getByText('AGW Dashboard', { exact: true })).toBeHidden();
});

test('local documentation is packaged and defaults to Chinese', async ({
  page,
}) => {
  await page.goto('/ui/docs/');

  await expect(page).toHaveTitle(/AGW 文档/);
  await expect(page.locator('body')).toContainText('快速导航');
  await expect(page).toHaveURL(/#\/zh\/latest\/README/);
  expect(
    (await page.request.get('/ui/docs/zh/latest/plugins/_sidebar.md')).status()
  ).toBe(404);

  const architectureLink = page
    .locator('a[href*="/zh/latest/architecture-design/apisix"]')
    .first();
  await expect(architectureLink).toBeVisible();
  await architectureLink.click();
  await expect(page).toHaveURL(
    /#\/zh\/latest\/architecture-design\/apisix/
  );
  await expect(page.locator('.markdown-section')).toContainText(
    '动态、实时、高性能'
  );
  const architectureImage = page.locator('.markdown-section img').first();
  await expect(architectureImage).toBeVisible();
  await expect
    .poll(() =>
      architectureImage.evaluate((image: HTMLImageElement) => image.naturalWidth)
    )
    .toBeGreaterThan(0);

  await page
    .locator('.markdown-section')
    .getByRole('link', { name: '插件文档' })
    .click();
  await expect(page).toHaveURL(/#\/zh\/latest\/plugins\/batch-requests/);
  await expect(page.locator('.markdown-section')).toContainText('batch-requests');
  await expect(
    page.locator('.sidebar-nav a').filter({ hasText: 'Installation Guide' })
  ).toBeVisible();
  await expect(page.locator('.sidebar-nav')).not.toContainText('AGW Dashboard');

  await page.goto('/ui/docs/#/en/latest/README');
  await expect(page.locator('body')).toContainText('Quick Links');
});

test('route detail renders', async ({ page }) => {
  await authenticate(page);
  await page.goto('/ui/routes/detail/ui-smoke-route');

  await expect(
    page.getByRole('heading', { name: /Route · ui-smoke-route/ })
  ).toBeVisible();
  await expect(page.getByText('Something went wrong')).toHaveCount(0);
});

test('SSL detail tolerates hidden private keys', async ({ page }) => {
  await authenticate(page);
  await page.goto('/ui/ssls/detail/ui-smoke-ssl');

  await expect(
    page.getByRole('heading', { name: /SSL · ui-smoke-ssl/ })
  ).toBeVisible();
  await expect(page.getByText('Something went wrong')).toHaveCount(0);
  await expect(page.getByText('Certificate 1')).toBeVisible();
});
