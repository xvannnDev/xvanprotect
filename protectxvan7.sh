#!/bin/bash
set -e

REMOTE_PATH="/var/www/pterodactyl/app/Http/Controllers/Admin/ApiController.php"
TIMESTAMP=$(date -u +"%Y-%m-%d-%H-%M-%S")
BACKUP_PATH="${REMOTE_PATH}.bak_${TIMESTAMP}"

echo "🚀 Memasang Proteksi Anti Akses Application API..."

# backup
if [ -f "$REMOTE_PATH" ]; then
  cp -a "$REMOTE_PATH" "${BACKUP_PATH}"
  echo "📦 Backup saved -> ${BACKUP_PATH}"
else
  echo "⚠️ File not found: $REMOTE_PATH"
  exit 1
fi

# write patched controller
cat > "$REMOTE_PATH" << 'PHP'
<?php

namespace Pterodactyl\Http\Controllers\Admin;

use Illuminate\View\View;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Http\Response;
use Illuminate\Http\RedirectResponse;
use Prologue\Alerts\AlertsMessageBag;
use Pterodactyl\Models\ApiKey;
use Pterodactyl\Services\Acl\Api\AdminAcl;
use Pterodactyl\Http\Controllers\Controller;
use Illuminate\View\Factory as ViewFactory;
use Pterodactyl\Services\Api\KeyCreationService;
use Pterodactyl\Contracts\Repository\ApiKeyRepositoryInterface;
use Pterodactyl\Http\Requests\Admin\Api\StoreApplicationApiKeyRequest;

class ApiController extends Controller
{
    public function __construct(
        private AlertsMessageBag $alert,
        private ApiKeyRepositoryInterface $repository,
        private KeyCreationService $keyCreationService,
        private ViewFactory $view,
    ) {
    }

    /**
     * Proteksi: hanya user ID 1 yang boleh akses Application API.
     */
    private function protect()
    {
        $user = Auth::user();
        if (!$user || $user->id !== 1) {
            abort(403, 'LU MAU NGAPAIN MEK? 😹, 🚫 AKSES DITOLAK OLEH XVANNN, YAHAHAHA GA BISA CREATE PLTA 😹');
        }
    }

    public function index(Request $request): View
    {
        $this->protect();

        return $this->view->make('admin.api.index', [
            'keys' => $this->repository->getApplicationKeys($request->user()),
        ]);
    }

    public function create(): View
    {
        $this->protect();

        $resources = AdminAcl::getResourceList();
        sort($resources);

        return $this->view->make('admin.api.new', [
            'resources' => $resources,
            'permissions' => [
                'r'  => AdminAcl::READ,
                'rw' => AdminAcl::READ | AdminAcl::WRITE,
                'n'  => AdminAcl::NONE,
            ],
        ]);
    }

    public function store(StoreApplicationApiKeyRequest $request): RedirectResponse
    {
        $this->protect();

        $this->keyCreationService->setKeyType(ApiKey::TYPE_APPLICATION)->handle([
            'memo' => $request->input('memo'),
            'user_id' => $request->user()->id,
        ], $request->getKeyPermissions());

        $this->alert->success('API key berhasil dibuat.')->flash();

        return redirect()->route('admin.api.index');
    }

    public function delete(Request $request, string $identifier): Response
    {
        $this->protect();

        $this->repository->deleteApplicationKey($request->user(), $identifier);

        return response('', 204);
    }
}
PHP

chmod 644 "$REMOTE_PATH"
chown www-data:www-data "$REMOTE_PATH" || true

echo "✅ Controller patched. Clearing Laravel caches..."

# clear caches so changes take effect
cd /var/www/pterodactyl || exit 1
php artisan cache:clear || true
php artisan config:clear || true
php artisan route:clear || true
php artisan view:clear || true
php artisan optimize:clear || true

# restart queue/web services (adjust service names if different)
if systemctl list-units --type=service --all | grep -q pteroq; then
  systemctl restart pteroq || true
fi
if systemctl list-units --type=service --all | grep -q nginx; then
  systemctl restart nginx || true
fi

echo "✅ Proteksi Anti Akses Application Api berhasil dipasang!"
echo "📂 Lokasi file: $REMOTE_PATH"
echo "🗂️ Backup file lama: ${BACKUP_PATH} (jika sebelumnya ada)"
echo "🔒 Hanya Admin (ID 1) yang bisa Akses Application Api."
