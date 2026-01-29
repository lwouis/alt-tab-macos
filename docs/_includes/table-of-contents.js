function slugify(text) {
    return text.toLowerCase().trim().replace(/[^\w\s-]/g, '').replace(/\s+/g, '-');
}

function buildTOC() {
    const urlParts = window.location.pathname.split('/');
    const currentPage = urlParts[urlParts.length - 1] || ""; // fallback
    const tocContainer = currentPage === "" ? document.querySelector('.submenu') : document.querySelector(`.submenu.${currentPage}`);
    if (!tocContainer) return;
    tocContainer.innerHTML = ''; // clear old TOC
    const headings = document.querySelectorAll('.content h1, .content h2');
    if (!headings.length || headings.length === 1) {
        tocContainer.style.display = 'none';
        return;
    }
    const usedIds = new Set();
    headings.forEach((heading) => {
        let id = heading.id;
        if (!id) {
            id = slugify(heading.textContent);
            let uniqueId = id;
            let i = 1;
            while (usedIds.has(uniqueId) || document.getElementById(uniqueId)) {
                uniqueId = `${id}-${i++}`;
            }
            id = uniqueId;
            heading.id = id;
        }
        usedIds.add(id);
        const li = document.createElement('li');
        li.className = `toc-${heading.tagName.toLowerCase()}`;
        const a = document.createElement('a');
        a.href = `#${id}`;
        a.textContent = heading.textContent;
        a.setAttribute('data-turbolinks', 'false');
        li.appendChild(a);
        tocContainer.appendChild(li);
    });

    const hash = window.location.hash;
    if (!hash) return;
    // remove existing .active, if exists
    const existingLink = document.querySelector(`.submenu a.active`);
    if (existingLink) {
        existingLink.classList.remove('active');
    }
    // add new .active, if exists
    const link = document.querySelector(`a[href="${hash}"]`);
    if (link) {
        link.classList.add('active');
    }
}

document.addEventListener('turbolinks:load', buildTOC);
window.addEventListener('hashchange', buildTOC);
