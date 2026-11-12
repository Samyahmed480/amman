/**
 * Amman AI — Full Chat Application State Machine & Engine
 * Compliant with Website Spec & Design Handoff (November 2026)
 */

document.addEventListener('DOMContentLoaded', () => {
  // Application State
  const state = {
    city: localStorage.getItem('amman_ai_city') || 'عمّان',
    area: localStorage.getItem('amman_ai_area') || 'خلدا',
    messagesCount: 0,
    guestLimit: 5,
    shoppingList: JSON.parse(localStorage.getItem('amman_ai_list') || '[]'),
    totalSavings: parseFloat(localStorage.getItem('amman_ai_savings') || '112.500'),
    activeFilters: {
      query: '',
      brand: '',
      category: '',
      retailer: '',
      size_value: '',
      sort_by: 'price_asc'
    },
    conversationHistory: [
      { id: 'c1', title: 'عروض حفاضات وزيوت هالأسبوع', date: 'اليوم 14:20', active: true },
      { id: 'c2', title: 'مؤونة البيت - رز وسكر', date: 'أمس', active: false },
      { id: 'c3', title: 'منظفات وصابون جلي', date: 'الخميس الماضي', active: false }
    ]
  };

  // Mock Database of Real Amman Retailer Deals (November 2026)
  const offersDatabase = [
    {
      id: 'off_001',
      retailer: 'كوزمو',
      branch: 'الدوار السابع',
      product_ar: 'حفاضات بامبرز عناية مميزة مقاس 5',
      brand: 'بامبرز',
      category: 'الأم والطفل',
      size_value: 5,
      size_unit: 'مقاس',
      pack_label: 'عبوة جامبو 54 حبة',
      price: 8.490,
      old_price: 11.800,
      discount_pct: 28.0,
      unit_price: '0.157 د.أ / حبة',
      valid_to: '2026-11-16',
      expiry_label: 'ينتهي بعد 4 أيام (16 نوفمبر)',
      is_sponsored: false,
      img: 'https://images.unsplash.com/photo-1515488042361-ee00e0ddd4e4?auto=format&fit=crop&w=300&q=80',
      lat: 31.9540,
      lng: 35.8560
    },
    {
      id: 'off_002',
      retailer: 'سي تاون',
      branch: 'الصويفية',
      product_ar: 'حفاضات بامبرز عناية مميزة مقاس 5',
      brand: 'بامبرز',
      category: 'الأم والطفل',
      size_value: 5,
      size_unit: 'مقاس',
      pack_label: 'عبوة جامبو 54 حبة',
      price: 8.990,
      old_price: 11.500,
      discount_pct: 21.8,
      unit_price: '0.166 د.أ / حبة',
      valid_to: '2026-11-18',
      expiry_label: 'ينتهي بعد 6 أيام (18 نوفمبر)',
      is_sponsored: false,
      img: 'https://images.unsplash.com/photo-1515488042361-ee00e0ddd4e4?auto=format&fit=crop&w=300&q=80',
      lat: 31.9610,
      lng: 35.8650
    },
    {
      id: 'off_003',
      retailer: 'سي تاون',
      branch: 'الصويفية',
      product_ar: 'زيت ذرة عافية نقي 1.5 لتر',
      brand: 'عافية',
      category: 'بقالة > زيوت',
      size_value: 1.5,
      size_unit: 'L',
      pack_label: 'عبوة 1.5 لتر',
      price: 2.850,
      old_price: 3.650,
      discount_pct: 21.9,
      unit_price: '1.900 د.أ / لتر',
      valid_to: '2026-11-15',
      expiry_label: 'ينتهي بعد 3 أيام (15 نوفمبر)',
      is_sponsored: true,
      img: 'https://images.unsplash.com/photo-1474979266404-7eaacbcd87c5?auto=format&fit=crop&w=300&q=80',
      lat: 31.9610,
      lng: 35.8650
    },
    {
      id: 'off_004',
      retailer: 'سيفوي',
      branch: 'الشميساني',
      product_ar: 'زيت ذرة مازولا 1.5 لتر',
      brand: 'مازولا',
      category: 'بقالة > زيوت',
      size_value: 1.5,
      size_unit: 'L',
      pack_label: 'عبوة 1.5 لتر',
      price: 2.990,
      old_price: 3.750,
      discount_pct: 20.3,
      unit_price: '1.993 د.أ / لتر',
      valid_to: '2026-11-17',
      expiry_label: 'ينتهي بعد 5 أيام (17 نوفمبر)',
      is_sponsored: false,
      img: 'https://images.unsplash.com/photo-1474979266404-7eaacbcd87c5?auto=format&fit=crop&w=300&q=80',
      lat: 31.9720,
      lng: 35.8950
    },
    {
      id: 'off_005',
      retailer: 'هايبرماكس',
      branch: 'سيتي مول',
      product_ar: 'طبق بيض مائدة طازج 30 بيضة (كبير)',
      brand: 'بلدي',
      category: 'ألبان وبيض',
      size_value: 30,
      size_unit: 'حبة',
      pack_label: 'طبق كرتون 30 حبة',
      price: 2.390,
      old_price: 2.950,
      discount_pct: 18.9,
      unit_price: '0.079 د.أ / بيضة',
      valid_to: '2026-11-18',
      expiry_label: 'ينتهي بعد 6 أيام (18 نوفمبر)',
      is_sponsored: false,
      img: 'https://images.unsplash.com/photo-1582722872445-44dc5f7e3c8f?auto=format&fit=crop&w=300&q=80',
      lat: 31.9880,
      lng: 35.8340
    },
    {
      id: 'off_006',
      retailer: 'سامح مول',
      branch: 'طبربور',
      product_ar: 'أرز صنوايت كالروز أسترالي 5 كغ',
      brand: 'صنوايت',
      category: 'بقالة > أرز',
      size_value: 5,
      size_unit: 'kg',
      pack_label: 'كيس 5 كغ',
      price: 4.890,
      old_price: 6.250,
      discount_pct: 21.7,
      unit_price: '0.978 د.أ / كغ',
      valid_to: '2026-11-19',
      expiry_label: 'ينتهي بعد 7 أيام (19 نوفمبر)',
      is_sponsored: false,
      img: 'https://images.unsplash.com/photo-1586201375761-83865001e31c?auto=format&fit=crop&w=300&q=80',
      lat: 32.0010,
      lng: 35.9120
    }
  ];

  // DOM Elements
  const messagesScroll = document.getElementById('messagesScroll');
  const chatInput = document.getElementById('chatInput');
  const sendBtn = document.getElementById('sendBtn');
  const micBtn = document.getElementById('micBtn');
  const imageUploadBtn = document.getElementById('imageUploadBtn');
  const locationBtn = document.getElementById('locationBtn');
  const suggestionChips = document.querySelectorAll('.chip-action');
  
  // Drawers & Modals
  const sidebar = document.getElementById('appSidebar');
  const drawerPanel = document.getElementById('drawerPanel');
  const sidebarToggle = document.getElementById('sidebarToggle');
  const drawerToggle = document.getElementById('drawerToggle');
  const drawerCloseBtn = document.getElementById('drawerCloseBtn');
  const listCountBadge = document.getElementById('listCountBadge');
  const drawerListContainer = document.getElementById('drawerListContainer');
  const drawerTotalSum = document.getElementById('drawerTotalSum');
  const drawerSavingsSum = document.getElementById('drawerSavingsSum');
  
  // Theme Toggle
  const themeToggle = document.getElementById('themeToggle');
  const currentTheme = localStorage.getItem('amman_ai_theme') || 'light';
  document.documentElement.setAttribute('data-theme', currentTheme);

  if (themeToggle) {
    themeToggle.addEventListener('click', () => {
      const active = document.documentElement.getAttribute('data-theme') || 'light';
      const target = active === 'dark' ? 'light' : 'dark';
      document.documentElement.setAttribute('data-theme', target);
      localStorage.setItem('amman_ai_theme', target);
    });
  }

  // City Selector Dropdown
  const cityBadgeBtn = document.getElementById('cityBadgeBtn');
  if (cityBadgeBtn) {
    cityBadgeBtn.addEventListener('click', () => {
      promptCitySelect();
    });
  }

  // Drawers Toggle Handlers
  if (sidebarToggle && sidebar) {
    sidebarToggle.addEventListener('click', () => {
      sidebar.classList.toggle('open');
      if (drawerPanel) drawerPanel.classList.remove('open');
    });
  }

  if (drawerToggle && drawerPanel) {
    drawerToggle.addEventListener('click', () => {
      drawerPanel.classList.toggle('open');
      if (sidebar) sidebar.classList.remove('open');
      renderShoppingList();
    });
  }

  if (drawerCloseBtn && drawerPanel) {
    drawerCloseBtn.addEventListener('click', () => {
      drawerPanel.classList.remove('open');
    });
  }

  // Update Shopping List UI
  function updateListBadge() {
    if (listCountBadge) {
      listCountBadge.textContent = state.shoppingList.length;
      listCountBadge.style.display = state.shoppingList.length > 0 ? 'inline-flex' : 'none';
    }
  }

  function renderShoppingList() {
    if (!drawerListContainer) return;
    if (state.shoppingList.length === 0) {
      drawerListContainer.innerHTML = `
        <div style="text-align: center; padding: 2.5rem 1rem; color: var(--text-muted);">
          <svg width="44" height="44" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" style="margin: 0 auto 0.75rem auto;"><circle cx="9" cy="21" r="1"/><circle cx="20" cy="21" r="1"/><path d="M1 1h4l2.68 13.39a2 2 0 0 0 2 1.61h9.72a2 2 0 0 0 2-1.61L23 6H6"/></svg>
          <p style="font-weight: 700; margin-bottom: 0.25rem;">قائمتك فاضية</p>
          <p style="font-size: 0.85rem;">اضغط «أضف للقائمة» على أي عرض بيعجبك أثناء المحادثة.</p>
        </div>
      `;
      if (drawerTotalSum) drawerTotalSum.textContent = '0.000 د.أ';
      if (drawerSavingsSum) drawerSavingsSum.textContent = '0.000 د.أ';
      return;
    }

    // Group items by store
    const grouped = {};
    let totalJod = 0;
    let savingsJod = 0;

    state.shoppingList.forEach(item => {
      if (!grouped[item.retailer]) grouped[item.retailer] = [];
      grouped[item.retailer].push(item);
      totalJod += item.price;
      savingsJod += (item.old_price - item.price);
    });

    let html = '';
    for (const [store, items] of Object.entries(grouped)) {
      html += `
        <div class="store-list-group">
          <div class="store-group-header">
            <span>
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="display:inline; margin-left: 4px;"><path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/></svg>
              ${store} (${items.length})
            </span>
            <span style="font-family: var(--font-latin);">${items.reduce((acc, c) => acc + c.price, 0).toFixed(3)} د.أ</span>
          </div>
          <div class="store-group-items">
            ${items.map((it, idx) => `
              <div class="store-item-row">
                <div>
                  <div style="font-weight: 700;">${it.product_ar}</div>
                  <div style="font-size: 0.75rem; color: var(--text-muted);">${it.pack_label}</div>
                </div>
                <div style="text-align: left;">
                  <span style="font-weight: 800; font-family: var(--font-latin);">${it.price.toFixed(3)} د.أ</span>
                  <button onclick="window.removeListItem('${it.id}')" style="margin-right: 6px; color: var(--color-danger); font-size: 0.85rem;">✕</button>
                </div>
              </div>
            `).join('')}
          </div>
        </div>
      `;
    }

    drawerListContainer.innerHTML = html;
    if (drawerTotalSum) drawerTotalSum.textContent = `${totalJod.toFixed(3)} د.أ`;
    if (drawerSavingsSum) drawerSavingsSum.textContent = `${savingsJod.toFixed(3)} د.أ`;
  }

  window.removeListItem = (id) => {
    state.shoppingList = state.shoppingList.filter(item => item.id !== id);
    localStorage.setItem('amman_ai_list', JSON.stringify(state.shoppingList));
    updateListBadge();
    renderShoppingList();
  };

  window.addDealToList = (dealId) => {
    const deal = offersDatabase.find(d => d.id === dealId);
    if (!deal) return;
    if (!state.shoppingList.some(item => item.id === dealId)) {
      state.shoppingList.push(deal);
      localStorage.setItem('amman_ai_list', JSON.stringify(state.shoppingList));
      updateListBadge();
      showToast(`تمت إضافة «${deal.product_ar}» إلى قائمة التسوق بنجاح!`);
    } else {
      showToast(`هذا الصنف موجود بالفعل في قائمتك.`);
    }
  };

  window.reportDeal = (dealId) => {
    const deal = offersDatabase.find(d => d.id === dealId);
    showModal({
      title: 'إبلاغ عن سعر غير دقيق',
      body: `
        <p style="font-size: 0.9rem; color: var(--text-secondary); margin-bottom: 1rem;">
          نحن ملتزمون بدقة 100%. أبلغنا إن كان السعر أو العرض مختلفاً على أرض الواقع في <strong>${deal ? deal.retailer : 'المتجر'}</strong>:
        </p>
        <div style="display:flex; flex-direction:column; gap: 0.5rem; margin-bottom: 1rem;">
          <label style="font-size: 0.85rem;"><input type="radio" name="report_reason" value="wrong_price" checked> السعر في المتجر أعلى من المعروض</label>
          <label style="font-size: 0.85rem;"><input type="radio" name="report_reason" value="out_of_stock"> العرض نفد أو غير متوفر في هذا الفرع</label>
          <label style="font-size: 0.85rem;"><input type="radio" name="report_reason" value="expired"> العرض منتهي الصلاحية</label>
        </div>
        <textarea id="reportNotes" class="mock-input-field" placeholder="أي ملاحظات إضافية..." style="width: 100%; border-radius: 12px; height: 70px;"></textarea>
      `,
      confirmText: 'إرسال البلاغ',
      onConfirm: () => {
        showToast('شكراً لمساعدتك! تم تسجيل البلاغ وسيقوم الفريق بالتحقق فوراً.');
      }
    });
  };

  window.setPriceAlert = (productName) => {
    showModal({
      title: 'إنشاء تنبيه هبوط السعر',
      body: `
        <p style="font-size: 0.9rem; color: var(--text-secondary); margin-bottom: 1rem;">
          سنرسل لك إشعاراً فورياً (Web Push) عند نزول أي عرض جديد على <strong>${productName}</strong> في عمّان:
        </p>
        <div style="display:flex; gap: 0.5rem; align-items:center;">
          <input type="number" id="targetPriceInput" class="mock-input-field" placeholder="السعر المطلوب (مثلاً: 2.500)" step="0.1" style="flex:1;">
          <span style="font-weight: 700;">د.أ</span>
        </div>
      `,
      confirmText: 'تفعيل التنبيه',
      onConfirm: () => {
        showToast(`تم تفعيل التنبيه لـ «${productName}».`);
      }
    });
  };

  window.openDirections = (lat, lng, retailer) => {
    window.open(`https://www.google.com/maps/search/?api=1&query=${lat},${lng}`, '_blank');
  };

  window.shareDeal = (productName, price, retailer) => {
    if (navigator.share) {
      navigator.share({
        title: `عرض ${productName} على Amman AI`,
        text: `لقيت عرض ممتاز على ${productName} بـ ${price} د.أ في ${retailer} عبر مساعد عمان للتسوق!`,
        url: window.location.href
      }).catch(() => {});
    } else {
      navigator.clipboard.writeText(`عرض ${productName} بـ ${price} د.أ في ${retailer} - شاهد التفاصيل على Amman AI: ${window.location.href}`);
      showToast('تم نسخ رابط العرض للمشاركة.');
    }
  };

  // Toast System
  function showToast(msg) {
    let toast = document.getElementById('globalToast');
    if (!toast) {
      toast = document.createElement('div');
      toast.id = 'globalToast';
      toast.style.cssText = `
        position: fixed;
        bottom: 85px;
        left: 50%;
        transform: translateX(-50%);
        background: var(--primary-navy);
        color: #FFFFFF;
        padding: 0.75rem 1.5rem;
        border-radius: var(--radius-pill);
        font-size: 0.9rem;
        font-weight: 700;
        box-shadow: var(--shadow-lg);
        z-index: 10000;
        transition: all 0.25s ease;
        opacity: 0;
        pointer-events: none;
      `;
      document.body.appendChild(toast);
    }
    toast.textContent = msg;
    toast.style.opacity = '1';
    toast.style.transform = 'translateX(-50%) translateY(0)';
    setTimeout(() => {
      toast.style.opacity = '0';
      toast.style.transform = 'translateX(-50%) translateY(10px)';
    }, 2800);
  }

  // Modal Dialog System
  function showModal({ title, body, confirmText = 'موافق', onConfirm = null }) {
    let overlay = document.getElementById('globalModalOverlay');
    if (!overlay) {
      overlay = document.createElement('div');
      overlay.id = 'globalModalOverlay';
      overlay.className = 'modal-overlay';
      overlay.innerHTML = `
        <div class="modal-dialog">
          <div style="display:flex; justify-content:space-between; align-items:center;">
            <h3 id="modalTitle" style="font-size: 1.25rem;"></h3>
            <button id="modalCloseBtn" style="font-size: 1.25rem; color:var(--text-muted);">✕</button>
          </div>
          <div id="modalBody"></div>
          <div style="display:flex; justify-content:flex-end; gap:0.75rem; margin-top:0.5rem;">
            <button id="modalCancelBtn" class="btn btn-secondary btn-sm">إلغاء</button>
            <button id="modalConfirmBtn" class="btn btn-primary btn-sm"></button>
          </div>
        </div>
      `;
      document.body.appendChild(overlay);

      overlay.querySelector('#modalCloseBtn').onclick = () => overlay.classList.remove('open');
      overlay.querySelector('#modalCancelBtn').onclick = () => overlay.classList.remove('open');
    }

    overlay.querySelector('#modalTitle').textContent = title;
    overlay.querySelector('#modalBody').innerHTML = body;
    const confirmBtn = overlay.querySelector('#modalConfirmBtn');
    confirmBtn.textContent = confirmText;
    confirmBtn.onclick = () => {
      if (onConfirm) onConfirm();
      overlay.classList.remove('open');
    };

    overlay.classList.add('open');
  }

  // City Prompting State Machine
  function promptCitySelect() {
    showModal({
      title: 'اختر مدينتك في الأردن',
      body: `
        <p style="font-size:0.9rem; color:var(--text-secondary); margin-bottom:1rem;">
          عروض المتاجر والفروع تختلف بحسب المحافظة. اختر منطقتك لنعرض لك أقرب وأدق الأسعار:
        </p>
        <div style="display:grid; grid-template-columns: repeat(2, 1fr); gap: 0.65rem;">
          ${['عمّان', 'الزرقاء', 'إربد', 'العقبة', 'السلط', 'مادبا'].map(c => `
            <button class="btn btn-secondary btn-sm city-option-btn" data-city="${c}" style="justify-content: flex-start;">
              📍 ${c}
            </button>
          `).join('')}
        </div>
      `,
      confirmText: 'حفظ المدينة',
      onConfirm: () => {}
    });

    setTimeout(() => {
      document.querySelectorAll('.city-option-btn').forEach(btn => {
        btn.addEventListener('click', () => {
          const c = btn.getAttribute('data-city');
          state.city = c;
          localStorage.setItem('amman_ai_city', c);
          if (cityBadgeBtn) cityBadgeBtn.querySelector('span').textContent = `${c} · ${state.area}`;
          document.getElementById('globalModalOverlay').classList.remove('open');
          showToast(`تم ضبط مدينتك على: ${c}`);
        });
      });
    }, 100);
  }

  // Chat Streaming & Message Renderer
  function appendUserMessage(text) {
    const row = document.createElement('div');
    row.className = 'message-row';
    row.innerHTML = `<div class="bubble-user">${text}</div>`;
    messagesScroll.appendChild(row);
    messagesScroll.scrollTop = messagesScroll.scrollHeight;
    state.messagesCount++;

    // Check guest limit (5 messages)
    if (state.messagesCount >= state.guestLimit) {
      setTimeout(() => {
        showGuestRegistrationBanner();
      }, 1000);
    }
  }

  function showGuestRegistrationBanner() {
    showModal({
      title: 'حفظ سجل محادثاتك وسلّة العيلة',
      body: `
        <div style="text-align:center; padding: 0.5rem 0;">
          <div style="width: 50px; height: 50px; border-radius: 50%; background: var(--surface-light); display:flex; align-items:center; justify-content:center; margin: 0 auto 1rem auto; color: var(--primary-navy);">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
          </div>
          <p style="font-size: 0.92rem; color: var(--text-primary); font-weight: 700; margin-bottom: 0.5rem;">
            لقد وصلت للحد المجاني لتجربة الزوار (5 استفسارات).
          </p>
          <p style="font-size: 0.85rem; color: var(--text-secondary); margin-bottom: 1.25rem;">
            سجّل دخولك المجاني عبر Google أو رقم هاتفك الأردني لتحفظ قائمتك وتفعّل عدّاد التوفير وتنبيهات الأسعار.
          </p>
          <button class="btn btn-primary" style="width: 100%; margin-bottom: 0.5rem;" onclick="alert('تسجيل الدخول عبر Google');">
            المتابعة باستخدام Google
          </button>
        </div>
      `,
      confirmText: 'المتابعة كزائر مؤقتاً'
    });
  }

  function appendAgentResponse(rawText, deals = [], clarificationOptions = []) {
    const row = document.createElement('div');
    row.className = 'message-row';

    const bubble = document.createElement('div');
    bubble.className = 'bubble-agent';
    bubble.innerHTML = `<span class="typing-cursor"></span>`;
    row.appendChild(bubble);

    // Feedback row (thumbs + retry)
    const feedbackRow = document.createElement('div');
    feedbackRow.className = 'message-feedback-row';
    feedbackRow.innerHTML = `
      <button class="btn-feedback" title="مفيد" onclick="this.style.color='var(--color-success)';">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 9V5a3 3 0 0 0-3-3l-4 9v11h11.28a2 2 0 0 0 2-1.7l1.38-9a2 2 0 0 0-2-2.3zM7 22H4a2 2 0 0 1-2-2v-7a2 2 0 0 1 2-2h3"/></svg>
      </button>
      <button class="btn-feedback" title="غير دقيق" onclick="this.style.color='var(--color-danger)';">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M10 15v4a3 3 0 0 0 3 3l4-9V2H5.72a2 2 0 0 0-2 1.7l-1.38 9a2 2 0 0 0 2 2.3zm7-13h3a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2h-3"/></svg>
      </button>
      <button class="btn-retry-action" onclick="window.retryLastQuery()">
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M1 4v6h6M23 20v-6h-6"/><path d="M20.49 9A9 9 0 0 0 5.64 5.64L1 10m22 4l-4.64 4.36A9 9 0 0 1 3.51 15"/></svg>
        أعد المحاولة
      </button>
    `;

    messagesScroll.appendChild(row);
    messagesScroll.scrollTop = messagesScroll.scrollHeight;

    // Simulate streaming text typewriter
    let charIndex = 0;
    const speed = 12;
    const interval = setInterval(() => {
      charIndex += 2;
      if (charIndex >= rawText.length) {
        clearInterval(interval);
        renderCompleteCards();
      } else {
        bubble.innerHTML = rawText.substring(0, charIndex) + `<span class="typing-cursor"></span>`;
        messagesScroll.scrollTop = messagesScroll.scrollHeight;
      }
    }, speed);

    function renderCompleteCards() {
      let cardsHtml = `<p>${rawText}</p>`;

      if (clarificationOptions.length > 0) {
        cardsHtml += `
          <div style="display:flex; gap:0.5rem; flex-wrap:wrap; margin-top:0.75rem;">
            ${clarificationOptions.map(opt => `
              <button class="chip" onclick="window.sendDirectQuery('${opt}')">${opt}</button>
            `).join('')}
          </div>
        `;
      }

      if (deals.length > 0) {
        deals.forEach((d, idx) => {
          cardsHtml += `
            <div class="deal-card">
              <div class="deal-card-header">
                <span class="deal-card-number">العرض ${idx + 1}</span>
                <span class="deal-card-retailer">
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/></svg>
                  ${d.retailer} · ${d.branch}
                </span>
                ${d.is_sponsored ? '<span class="badge badge-sponsored">مموّل</span>' : ''}
              </div>
              <div class="deal-card-body">
                <div class="deal-card-img-wrap">
                  <img src="${d.img}" alt="${d.product_ar}" onerror="this.src='amman_ai_logo.jpg'">
                </div>
                <div class="deal-card-info">
                  <div class="deal-product-name">${d.product_ar}</div>
                  <div class="deal-product-pack">${d.pack_label}</div>
                  <div class="deal-pricing-row">
                    <span class="deal-price-current">${d.price.toFixed(3)} د.أ</span>
                    <span class="deal-price-old">${d.old_price.toFixed(3)} د.أ</span>
                    <span class="badge badge-discount">-%${d.discount_pct.toFixed(1)}</span>
                  </div>
                  <span class="deal-unit-price">${d.unit_price}</span>
                  <div class="deal-expiry-row">
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/></svg>
                    ${d.expiry_label}
                  </div>
                </div>
              </div>
              <div class="deal-actions-row">
                <div class="deal-action-buttons-group">
                  <button class="btn-card-action btn-add-list" onclick="window.addDealToList('${d.id}')">
                    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M12 5v14M5 12h14"/></svg>
                    أضف للقائمة
                  </button>
                  <button class="btn-card-action" onclick="window.openDirections(${d.lat}, ${d.lng}, '${d.retailer}')">
                    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/></svg>
                    الاتجاهات
                  </button>
                  <button class="btn-card-action" onclick="window.shareDeal('${d.product_ar}', '${d.price.toFixed(3)}', '${d.retailer}')">
                    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><line x1="8.59" y1="13.51" x2="15.42" y2="17.49"/><line x1="15.41" y1="6.51" x2="8.59" y2="10.49"/></svg>
                    شارك
                  </button>
                  <button class="btn-card-action" onclick="window.setPriceAlert('${d.product_ar}')">
                    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/></svg>
                    نبهني
                  </button>
                </div>
                <button class="btn-report-wrong" onclick="window.reportDeal('${d.id}')">السعر غلط؟</button>
              </div>
            </div>
          `;
        });
      }

      bubble.innerHTML = cardsHtml;
      row.appendChild(feedbackRow);
      messagesScroll.scrollTop = messagesScroll.scrollHeight;
    }
  }

  // Processing Query Logic (Multi-turn filter stacking)
  let lastQuery = '';
  window.retryLastQuery = () => {
    if (lastQuery) handleUserInput(lastQuery);
  };

  window.sendDirectQuery = (queryText) => {
    if (chatInput) chatInput.value = queryText;
    handleUserInput(queryText);
  };

  function handleUserInput(input) {
    const text = input.trim();
    if (!text) return;
    lastQuery = text;

    appendUserMessage(text);
    if (chatInput) chatInput.value = '';

    // Multi-turn Intent Parsing
    setTimeout(() => {
      processAgentLogic(text);
    }, 400);
  }

  function processAgentLogic(text) {
    const lower = text.toLowerCase();

    // Turn: Add cheapest to list
    if (lower.includes('ضيف') && (lower.includes('قايمة') || lower.includes('قائمة') || lower.includes('ارخص') || lower.includes('أرخص'))) {
      const cheapest = offersDatabase[0];
      window.addDealToList(cheapest.id);
      appendAgentResponse(`أبشر! ضفتلك «${cheapest.product_ar}» من ${cheapest.retailer} بـ ${cheapest.price.toFixed(3)} د.أ على قائمتك. صار بقائمتك ${state.shoppingList.length} أصناف.`);
      return;
    }

    // Turn: Family Basket inquiry
    if (lower.includes('سلة') || lower.includes('سلّة') || lower.includes('مؤونة')) {
      appendAgentResponse(
        `سلّة العيلة الأسبوعية جاهزة! حسبتلك أرخص توزيع بين المتاجر لعائلة 5 أفراد:\n` +
        `• الرز والزيت من كوزمو (السابع): 10.340 د.أ\n` +
        `• الحليب والبيض من سيفوي (الشميساني): 6.750 د.أ\n` +
        `المجموع الإجمالي: 17.090 د.أ (وفّرت 3.810 د.أ مقارنة بالأسعار العادية).`,
        [offersDatabase[2], offersDatabase[4]],
        ['حوّلها لقائمة كاملة', 'متجر واحد فقط']
      );
      return;
    }

    // Turn: Diapers / Pampers filter
    if (lower.includes('حفاضات') || lower.includes('بامبرز') || lower.includes('مقاس 5')) {
      let filtered = offersDatabase.filter(o => o.category.includes('الأم والطفل') || o.brand.includes('بامبرز'));
      if (lower.includes('كوزمو')) {
        filtered = filtered.filter(o => o.retailer.includes('كوزمو'));
        appendAgentResponse(`لقيتلك عرض حفاضات بامبرز مقاس 5 في كوزمو (الدوار السابع): سعر العبوة 8.490 د.أ بتوفير 28% وسعر الحبة 0.157 د.أ (أرخص سعر وحدة بعمّان).`, filtered);
      } else if (lower.includes('سيفوي')) {
        appendAgentResponse(`في سيفوي هالأسبوع عبوة بامبرز مقاس 5 سعرها 9.150 د.أ. العرض 1 في كوزمو يظل أوفر بـ 66 قرش.`, filtered);
      } else {
        appendAgentResponse(`لقيت عرضين لحفاضات بامبرز مقاس 5 سارية اليوم في عمّان. العرض 1 في كوزمو هو الأرخص بسعر الوحدة:`, filtered, ['وبكوزمو بس؟', 'طيب وبسيفوي؟']);
      }
      return;
    }

    // Turn: Cooking Oil / Mazola
    if (lower.includes('زيت') || lower.includes('عافية') || lower.includes('مازولا')) {
      const filtered = offersDatabase.filter(o => o.category.includes('زيوت'));
      appendAgentResponse(`لقيتلك أقوى عروض زيت الذرة 1.5 لتر بعمّان هالأسبوع: سي تاون مسوي أفضل سعر مباشر بـ 2.850 د.أ (العرض 1)، ومازولا بسيفوي بـ 2.990 د.أ (العرض 2).`, filtered, ['رتب حسب الأقرب', 'أرخص زيت زيتون']);
      return;
    }

    // Turn: Eggs
    if (lower.includes('بيض')) {
      const filtered = offersDatabase.filter(o => o.category.includes('ألبان وبيض'));
      appendAgentResponse(`أرخص طبق بيض مائدة طازج 30 بيضة موجود اليوم بهايبرماكس (سيتي مول) بـ 2.390 د.أ (سعر البيضة أقل من 8 قروش). العرض ساري حتى 18 نوفمبر.`, filtered);
      return;
    }

    // Turn: Rice
    if (lower.includes('رز') || lower.includes('أرز') || lower.includes('صنوايت')) {
      const filtered = offersDatabase.filter(o => o.category.includes('أرز'));
      appendAgentResponse(`أرز صنوايت كالروز الأسترالي كيس 5 كغ نازل عليه عرض قوي بسامح مول (طبربور) بـ 4.890 د.أ بدل 6.250 د.أ (وفرت دينار و 36 قرش).`, filtered);
      return;
    }

    // General fallback search
    appendAgentResponse(`بحثت في قاعدة العروض بـ ${state.city} عن «${text}»:\nإليك أقوى العروض المطابقة ذات أعلى نسبة خصم سارية اليوم:`, [offersDatabase[0], offersDatabase[2]], ['الأرخص سعراً', 'الأقرب لموقعي']);
  }

  // Input Listeners
  if (sendBtn && chatInput) {
    sendBtn.addEventListener('click', () => handleUserInput(chatInput.value));
    chatInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') handleUserInput(chatInput.value);
    });
  }

  suggestionChips.forEach(chip => {
    chip.addEventListener('click', () => {
      const q = chip.getAttribute('data-query');
      if (q) handleUserInput(q);
    });
  });

  // Voice Search Simulation
  if (micBtn) {
    micBtn.addEventListener('click', () => {
      showModal({
        title: 'البحث الصوتي الذكي (لهجة أردنية)',
        body: `
          <div style="text-align:center; padding: 1.5rem 0;">
            <div style="width: 70px; height: 70px; border-radius: 50%; background: var(--color-discount-bg); color: var(--color-discount); display: flex; align-items:center; justify-content:center; margin: 0 auto 1rem auto; animation: pulse 1.5s infinite;">
              <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" y1="19" x2="12" y2="23"/><line x1="8" y1="23" x2="16" y2="23"/></svg>
            </div>
            <p style="font-weight: 700; margin-bottom: 0.25rem;">جاري الاستماع...</p>
            <p style="font-size: 0.85rem; color: var(--text-secondary);">تكلّم بطبيعتك: «بدي أرخص زيت ذرة بعمّان» أو «عروض كوزمو هالأسبوع»</p>
          </div>
        `,
        confirmText: 'تم التحدث',
        onConfirm: () => {
          handleUserInput('بدي أرخص زيت ذرة 1.5 لتر بعمّان');
        }
      });
    });
  }

  // Image Upload Simulation (Vision AI)
  if (imageUploadBtn) {
    imageUploadBtn.addEventListener('click', () => {
      showModal({
        title: 'البحث بالصورة أو الإيصال (Vision AI)',
        body: `
          <div style="text-align:center; padding: 1rem 0;">
            <div style="border: 2px dashed var(--border-subtle); border-radius: var(--radius-card-sm); padding: 2rem 1rem; cursor: pointer; background: var(--surface-light);">
              <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="margin: 0 auto 0.5rem auto; color: var(--primary-navy);"><rect x="3" y="3" width="18" height="18" rx="2" ry="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/></svg>
              <p style="font-weight: 700; font-size: 0.95rem;">ارفع صورة المنتج أو صورة فاتورة مشترياتك</p>
              <p style="font-size: 0.8rem; color: var(--text-muted); margin-top: 0.25rem;">سيتعرف الوكيل فوراً على الصنف ويستخرج عروضه أو يحسب التوفير المحقق.</p>
            </div>
          </div>
        `,
        confirmText: 'فحص الصورة',
        onConfirm: () => {
          showToast('تم فحص الصورة بنجاح بواسطة Vision AI.');
          handleUserInput('حفاضات بامبرز مقاس 5');
        }
      });
    });
  }

  // Location Button Handler
  if (locationBtn) {
    locationBtn.addEventListener('click', () => {
      if (navigator.geolocation) {
        showToast('جاري تحديد موقعك الجغرافي عبر GPS...');
        navigator.geolocation.getCurrentPosition(
          (pos) => {
            state.area = 'خلدا / دابوق';
            if (cityBadgeBtn) cityBadgeBtn.querySelector('span').textContent = `${state.city} · ${state.area}`;
            showToast(`تم تحديد موقعك: عمّان (قرب خلدا) - ترتيب العروض حسب الأقرب لك.`);
            handleUserInput('العروض القريبة مني');
          },
          (err) => {
            showToast('تعذر جلب الموقع الدقيق. تم اعتماد عمّان (خلدا) كمنطقة افتراضية.');
          }
        );
      }
    });
  }

  // Initial Boot
  updateListBadge();
  renderShoppingList();
});
