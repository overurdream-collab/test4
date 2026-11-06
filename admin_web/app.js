const STORAGE = {
  api: 'qatlink.admin.api',
  tokens: 'qatlink.admin.tokens',
  device: 'qatlink.admin.device',
};

const state = {
  apiBase: localStorage.getItem(STORAGE.api) || 'http://localhost:8080',
  phone: '',
  tokens: readTokens(),
  profile: null,
  busy: false,
};

const el = (id) => document.getElementById(id);
const loginView = el('login-view');
const dashboardView = el('dashboard-view');
const authMessage = el('auth-message');
const dashboardMessage = el('dashboard-message');
const phoneStep = el('phone-step');
const otpStep = el('otp-step');
const apiInput = el('api-url');
const phoneInput = el('phone');
const otpInput = el('otp');
const form = el('otp-form');
const toggle = el('sales-returns-toggle');

apiInput.value = state.apiBase;

function readTokens() {
  try {
    const raw = sessionStorage.getItem(STORAGE.tokens);
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

function saveTokens(tokens) {
  state.tokens = tokens;
  sessionStorage.setItem(STORAGE.tokens, JSON.stringify(tokens));
}

function clearTokens() {
  state.tokens = null;
  sessionStorage.removeItem(STORAGE.tokens);
}

function deviceId() {
  let value = localStorage.getItem(STORAGE.device);
  if (value && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)) {
    return value;
  }
  value = crypto.randomUUID();
  localStorage.setItem(STORAGE.device, value);
  return value;
}

function normalizePhone(value) {
  let phone = String(value || '').replace(/[^0-9+]/g, '');
  if (phone.startsWith('00')) phone = phone.slice(2);
  if (!phone.startsWith('+')) {
    if (phone.startsWith('967')) phone = `+${phone}`;
    else if (phone.startsWith('0')) phone = `+967${phone.slice(1)}`;
    else phone = `+967${phone}`;
  }
  return phone;
}

function setMessage(node, text, kind) {
  node.textContent = text || '';
  node.className = `message${kind ? ` ${kind}` : ''}`;
}

function setBusy(value) {
  state.busy = value;
  el('request-otp').disabled = value;
  el('verify-otp').disabled = value;
  el('change-phone').disabled = value;
  el('refresh').disabled = value;
  toggle.disabled = value || !toggle.dataset.ready;
}

async function refreshTokens() {
  const refreshToken = state.tokens?.refreshToken;
  if (!refreshToken) throw new Error('انتهت الجلسة. سجّل الدخول مرة أخرى.');
  const response = await fetch(`${state.apiBase}/v1/auth/refresh`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', accept: 'application/json' },
    body: JSON.stringify({ refreshToken }),
  });
  if (!response.ok) throw new Error('انتهت الجلسة. سجّل الدخول مرة أخرى.');
  const data = await response.json();
  saveTokens({
    ...state.tokens,
    accessToken: data.accessToken,
    refreshToken: data.refreshToken,
    expiresAt: data.expiresAt,
    refreshExpiresAt: data.refreshExpiresAt,
  });
}

async function api(path, options = {}, retry = true) {
  if (!state.apiBase) throw new Error('أدخل عنوان الخادم أولاً.');
  const headers = {
    accept: 'application/json',
    ...(options.body ? { 'content-type': 'application/json' } : {}),
    ...(options.headers || {}),
  };
  if (state.tokens?.accessToken) headers.authorization = `Bearer ${state.tokens.accessToken}`;
  const response = await fetch(`${state.apiBase}${path}`, { ...options, headers });
  let data = {};
  try { data = await response.json(); } catch {}
  if (response.status === 401 && retry && state.tokens?.refreshToken) {
    await refreshTokens();
    return api(path, options, false);
  }
  if (!response.ok) {
    const error = new Error(data.error || `HTTP ${response.status}`);
    error.status = response.status;
    error.code = data.error;
    throw error;
  }
  return data;
}

function errorText(error) {
  switch (error.code) {
    case 'invalid_or_expired_otp': return 'رمز التحقق غير صحيح أو منتهي الصلاحية.';
    case 'invalid_phone': return 'رقم الجوال غير صحيح.';
    case 'rate_limited': return 'محاولات كثيرة. انتظر قليلاً ثم أعد المحاولة.';
    case 'device_unavailable': return 'تعذر تسجيل هذا المتصفح.';
    case 'account_suspended': return 'الحساب موقوف. تواصل مع الدعم.';
    case 'forbidden': return 'هذا الحساب لا يملك صلاحية الإدارة.';
    default: return error.status >= 500 ? 'الخادم غير متاح حالياً.' : error.message;
  }
}

async function requestOtp(event) {
  event.preventDefault();
  if (state.busy) return;
  state.apiBase = apiInput.value.trim().replace(/\/+$/, '');
  localStorage.setItem(STORAGE.api, state.apiBase);
  state.phone = normalizePhone(phoneInput.value);
  setBusy(true);
  setMessage(authMessage, 'جارٍ إرسال الرمز...');
  try {
    await api('/v1/auth/otp/request', {
      method: 'POST',
      body: JSON.stringify({ phoneE164: state.phone }),
    });
    phoneStep.hidden = true;
    otpStep.hidden = false;
    otpInput.focus();
    setMessage(authMessage, 'أُرسل رمز التحقق. أدخله للمتابعة.', 'success');
  } catch (error) {
    setMessage(authMessage, errorText(error), 'error');
  } finally {
    setBusy(false);
  }
}

async function verifyOtp(event) {
  event.preventDefault();
  if (state.busy) return;
  const code = otpInput.value.trim();
  if (!/^\d{6}$/.test(code)) {
    setMessage(authMessage, 'أدخل رمزاً مكوناً من 6 أرقام.', 'error');
    return;
  }
  setBusy(true);
  setMessage(authMessage, 'جارٍ التحقق...');
  try {
    const data = await api('/v1/auth/otp/verify', {
      method: 'POST',
      body: JSON.stringify({
        phoneE164: state.phone,
        code,
        deviceId: deviceId(),
        deviceLabel: (navigator.userAgent || 'QAT LINK admin').slice(0, 100),
        platform: 'web',
      }),
    });
    saveTokens({
      accessToken: data.accessToken,
      refreshToken: data.refreshToken,
      expiresAt: data.expiresAt,
      refreshExpiresAt: data.refreshExpiresAt,
    });
    await openDashboard();
  } catch (error) {
    setMessage(authMessage, errorText(error), 'error');
  } finally {
    setBusy(false);
  }
}

function resetLogin() {
  phoneStep.hidden = false;
  otpStep.hidden = true;
  otpInput.value = '';
  setMessage(authMessage, '');
}

async function openDashboard() {
  setMessage(dashboardMessage, 'جارٍ تحميل البيانات...');
  try {
    const [me, service] = await Promise.all([
      api('/v1/me'),
      api('/v1/admin/service-controls/sales-returns'),
    ]);
    state.profile = me.user;
    el('admin-identity').textContent = `${me.user.displayName || me.user.phoneE164} • ${me.user.phoneE164}`;
    renderService(service);
    loginView.hidden = true;
    dashboardView.hidden = false;
    setMessage(dashboardMessage, '');
  } catch (error) {
    if (error.status === 401) {
      clearTokens();
      resetLogin();
      loginView.hidden = false;
      dashboardView.hidden = true;
    }
    throw error;
  }
}

function renderService(service) {
  const enabled = service.enabled === true;
  toggle.checked = enabled;
  toggle.dataset.ready = 'true';
  toggle.disabled = false;
  const statePill = el('service-state');
  statePill.textContent = enabled ? 'مفعّلة' : 'موقوفة';
  statePill.className = `pill ${enabled ? 'on' : 'off'}`;
  el('service-updated-at').textContent = service.updatedAt ? new Date(service.updatedAt).toLocaleString('ar-YE') : '—';
  el('service-updated-by').textContent = service.updatedByUserId || '—';
}

async function toggleService() {
  const next = toggle.checked;
  setBusy(true);
  setMessage(dashboardMessage, 'جارٍ حفظ التغيير...');
  try {
    const service = await api('/v1/admin/service-controls/sales-returns', {
      method: 'PATCH',
      body: JSON.stringify({ enabled: next }),
    });
    renderService(service);
    setMessage(dashboardMessage, 'تم حفظ التغيير.', 'success');
  } catch (error) {
    toggle.checked = !next;
    setMessage(dashboardMessage, errorText(error), 'error');
  } finally {
    setBusy(false);
    toggle.dataset.ready = 'true';
    toggle.disabled = false;
  }
}

async function refreshDashboard() {
  setBusy(true);
  setMessage(dashboardMessage, 'جارٍ التحديث...');
  try {
    const service = await api('/v1/admin/service-controls/sales-returns');
    renderService(service);
    setMessage(dashboardMessage, '');
  } catch (error) {
    setMessage(dashboardMessage, errorText(error), 'error');
  } finally {
    setBusy(false);
    toggle.dataset.ready = 'true';
    toggle.disabled = false;
  }
}

async function logout() {
  setBusy(true);
  try { await api('/v1/auth/logout', { method: 'POST', body: '{}' }); } catch {}
  clearTokens();
  state.profile = null;
  dashboardView.hidden = true;
  loginView.hidden = false;
  resetLogin();
  setMessage(authMessage, 'تم تسجيل الخروج.', 'success');
  setBusy(false);
}

form.addEventListener('submit', (event) => {
  if (otpStep.hidden) requestOtp(event);
  else verifyOtp(event);
});
el('change-phone').addEventListener('click', resetLogin);
el('refresh').addEventListener('click', refreshDashboard);
el('logout').addEventListener('click', logout);
toggle.addEventListener('change', toggleService);

if (state.tokens?.refreshToken) {
  openDashboard().catch((error) => {
    clearTokens();
    setMessage(authMessage, errorText(error), 'error');
  });
}
