/**
 * Amman AI — Landing Page Scripts
 * Interactive Hero Mock Chat, Theme Toggle & Accordions
 */

document.addEventListener('DOMContentLoaded', () => {
  // Theme Toggle Support
  const themeToggles = document.querySelectorAll('.theme-toggle-btn');
  const savedTheme = localStorage.getItem('amman_ai_theme') || 'light';
  
  function setTheme(theme) {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('amman_ai_theme', theme);
    themeToggles.forEach(btn => {
      btn.innerHTML = theme === 'dark' 
        ? `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="5"/><path d="M12 1v2M12 21v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M1 12h2M21 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42"/></svg>`
        : `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>`;
    });
  }
  
  setTheme(savedTheme);
  
  themeToggles.forEach(btn => {
    btn.addEventListener('click', () => {
      const current = document.documentElement.getAttribute('data-theme') || 'light';
      setTheme(current === 'dark' ? 'light' : 'dark');
    });
  });

  // FAQ Accordion
  const faqItems = document.querySelectorAll('.faq-item');
  faqItems.forEach(item => {
    const btn = item.querySelector('.faq-question-btn');
    if (btn) {
      btn.addEventListener('click', () => {
        const isOpen = item.classList.contains('open');
        faqItems.forEach(i => i.classList.remove('open'));
        if (!isOpen) {
          item.classList.add('open');
        }
      });
    }
  });

  // Hero Mock Chat Interactions
  const mockInput = document.getElementById('heroMockInput');
  const mockSendBtn = document.getElementById('heroMockSend');
  const mockConversation = document.getElementById('heroMockConversation');
  const mockChips = document.querySelectorAll('.mock-chip-trigger');

  const cannedAnswers = {
    'حفاضات': {
      text: 'لقيتلك أفضل عرض لحفاضات بامبرز مقاس 5 بعمّان هالأسبوع: كوزمو (الدوار السابع) مسوي خصم 28%. الكيس فيه 54 حبة بـ 8.490 د.أ وسعر الحبة 0.157 د.أ (أرخص من سيفوي بـ 75 قرش).',
      card: {
        number: 'العرض 1',
        retailer: 'كوزمو (السابع)',
        product: 'حفاضات بامبرز عناية مميزة مقاس 5',
        pack: 'عبوة جامبو 54 حبة',
        price: '8.490 د.أ',
        oldPrice: '11.800 د.أ',
        discount: '-%28.0',
        unitPrice: '0.157 د.أ / حبة',
        expiry: 'ينتهي السبت (15 نوفمبر)',
        img: 'https://images.unsplash.com/photo-1515488042361-ee00e0ddd4e4?auto=format&fit=crop&w=200&q=80'
      }
    },
    'زيت': {
      text: 'أرخص زيت ذرة 1.5 لتر بعمّان اليوم متوفر بسي تاون (الصويفية) بـ 2.850 د.أ (سعر اللتر 1.900 د.أ). العرض ساري حتى نفاد الكمية.',
      card: {
        number: 'العرض 1',
        retailer: 'سي تاون (الصويفية)',
        product: 'زيت ذرة عافية نقي 1.5 لتر',
        pack: 'عبوة بلاستيك 1.5L',
        price: '2.850 د.أ',
        oldPrice: '3.650 د.أ',
        discount: '-%21.9',
        unitPrice: '1.900 د.أ / لتر',
        expiry: 'ينتهي بعد 4 أيام (16 نوفمبر)',
        img: 'https://images.unsplash.com/photo-1474979266404-7eaacbcd87c5?auto=format&fit=crop&w=200&q=80'
      }
    },
    'بيض': {
      text: 'طبق بيض طازج 30 بيضة (وزن كبير) أرخص شي بهايبرماكس بـ 2.390 د.أ، مقارنة بـ 2.950 د.أ بالسعر العادي.',
      card: {
        number: 'العرض 1',
        retailer: 'هايبرماكس (سيتي مول)',
        product: 'طبق بيض مائدة طازج 30 بيضة (كبير)',
        pack: 'طبق كرتون 30 حبة',
        price: '2.390 د.أ',
        oldPrice: '2.950 د.أ',
        discount: '-%18.9',
        unitPrice: '0.079 د.أ / بيضة',
        expiry: 'ينتهي الأربعاء (18 نوفمبر)',
        img: 'https://images.unsplash.com/photo-1582722872445-44dc5f7e3c8f?auto=format&fit=crop&w=200&q=80'
      }
    }
  };

  function sendMockQuery(keyword) {
    if (!mockConversation) return;
    
    // Add User Bubble
    const userBubble = document.createElement('div');
    userBubble.className = 'bubble-user';
    userBubble.textContent = keyword;
    mockConversation.appendChild(userBubble);
    
    // Typing state
    const typingBubble = document.createElement('div');
    typingBubble.className = 'bubble-agent';
    typingBubble.innerHTML = `<span class="typing-cursor"></span> جاري البحث في عروض كوزمو، سي تاون، سيفوي وهايبرماكس...`;
    mockConversation.appendChild(typingBubble);
    mockConversation.scrollTop = mockConversation.scrollHeight;

    setTimeout(() => {
      let data = cannedAnswers['زيت'];
      if (keyword.includes('حفاضات') || keyword.includes('بامبرز')) data = cannedAnswers['حفاضات'];
      else if (keyword.includes('بيض')) data = cannedAnswers['بيض'];

      typingBubble.innerHTML = `
        <p>${data.text}</p>
        <div class="deal-card">
          <div class="deal-card-header">
            <span class="deal-card-number">${data.card.number}</span>
            <span class="deal-card-retailer">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/></svg>
              ${data.card.retailer}
            </span>
          </div>
          <div class="deal-card-body">
            <div class="deal-card-img-wrap">
              <img src="${data.card.img}" alt="${data.card.product}" onerror="this.src='amman_ai_logo.jpg'">
            </div>
            <div class="deal-card-info">
              <div class="deal-product-name">${data.card.product}</div>
              <div class="deal-product-pack">${data.card.pack}</div>
              <div class="deal-pricing-row">
                <span class="deal-price-current">${data.card.price}</span>
                <span class="deal-price-old">${data.card.oldPrice}</span>
                <span class="badge badge-discount">${data.card.discount}</span>
              </div>
              <span class="deal-unit-price">${data.card.unitPrice}</span>
              <div class="deal-expiry-row">
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/></svg>
                ${data.card.expiry}
              </div>
            </div>
          </div>
          <div class="deal-actions-row">
            <div class="deal-action-buttons-group">
              <button class="btn-card-action btn-add-list" onclick="window.location.href='app.html'">
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M12 5v14M5 12h14"/></svg>
                أضف للقائمة
              </button>
              <button class="btn-card-action" onclick="window.location.href='app.html'">
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/></svg>
                الاتجاهات
              </button>
            </div>
            <span class="btn-report-wrong">السعر غلط؟</span>
          </div>
        </div>
      `;
      mockConversation.scrollTop = mockConversation.scrollHeight;
    }, 650);
  }

  if (mockSendBtn && mockInput) {
    mockSendBtn.addEventListener('click', () => {
      const val = mockInput.value.trim();
      if (val) {
        sendMockQuery(val);
        mockInput.value = '';
      }
    });

    mockInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        const val = mockInput.value.trim();
        if (val) {
          sendMockQuery(val);
          mockInput.value = '';
        }
      }
    });
  }

  mockChips.forEach(chip => {
    chip.addEventListener('click', () => {
      const q = chip.getAttribute('data-query');
      if (q) sendMockQuery(q);
    });
  });
});
