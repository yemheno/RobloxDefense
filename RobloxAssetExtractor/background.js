chrome.action.onClicked.addListener((tab) => {
  chrome.scripting.executeScript({
    target: { tabId: tab.id },
    func: autoScrollAndScrape
  });
});

async function autoScrollAndScrape() {
    // 1. Create a dark overlay so you know the script is running
    let overlay = document.createElement('div');
    overlay.style.cssText = "position:fixed; top:0; left:0; width:100vw; height:100vh; background:rgba(0,0,0,0.85); color:#00FF00; z-index:999999; display:flex; flex-direction:column; justify-content:center; align-items:center; font-size:24px; font-family:monospace;";
    overlay.innerHTML = '<p id="scraper-status">Starting Auto-Scroll...</p>';
    document.body.appendChild(overlay);

    const status = document.getElementById('scraper-status');

    // 2. Auto-Scroll Loop
    let lastHeight = 0;
    let retries = 0;

    // Keep scrolling until it hits the bottom 3 times with no new items
    while (retries < 3) {
        status.innerText = `Scrolling to load more assets...`;
        window.scrollTo(0, document.body.scrollHeight);
        
        // Also scroll internal containers if Roblox uses them
        document.querySelectorAll('div').forEach(w => {
            if (w.scrollHeight > w.clientHeight && w.clientHeight > 500) {
                w.scrollTop = w.scrollHeight;
            }
        });
        
        await new Promise(r => setTimeout(r, 1500)); 

        let currentHeight = document.body.scrollHeight;
        if (currentHeight === lastHeight) {
            retries++; 
            status.innerText = `Waiting for more items... (Attempt ${retries}/3)`;
        } else {
            retries = 0; 
            lastHeight = currentHeight;
        }
    }

    status.innerText = "Finished scrolling! Scanning page for Asset IDs...";

    // 3. Extract the IDs from the page
    let assets = [];
    let seenIds = new Set();
    const elements = document.querySelectorAll('a, img');

    elements.forEach(el => {
        const linkStr = el.href || el.src || "";
        const matches = linkStr.match(/(\d{8,15})/g);
        
        if (matches && matches.length > 0) {
            const id = matches[matches.length - 1]; 
            
            // Try to find the name from text or image alt text
            let name = "";
            if (el.innerText && el.innerText.trim() !== "") {
                name = el.innerText.trim().split('\n')[0];
            } else if (el.alt && el.alt.trim() !== "") {
                name = el.alt.trim();
            }

            // EXCLUSION FILTER: Skip empty names or anything named just "Asset"
            if (!name || name.toLowerCase() === "asset") {
                return; // Skip this one entirely
            }
            
            if (!seenIds.has(id)) {
                seenIds.add(id);
                assets.push({ id, name });
            }
        }
    });

    if (assets.length === 0) {
        status.innerText = "No named assets found on this page!";
        status.style.color = "red";
        setTimeout(() => document.body.removeChild(overlay), 4000);
        return;
    }

    status.innerText = `Success! Found ${assets.length} items. Opening in new tab...`;

    // 4. Generate the HTML Content
    let htmlContent = `
    <html>
    <head><title>Roblox Asset IDs</title></head>
    <body style="font-family: sans-serif; padding: 20px; background-color: #f2f4f5;">
        <h2>Extracted Asset IDs (${assets.length})</h2>
        <p><em>Note: Generic UI buttons and empty names were excluded.</em></p>
        <table border="1" cellpadding="8" style="border-collapse: collapse; background-color: white; width: 100%; max-width: 600px;">
            <tr style="background-color: #000; color: #fff;">
                <th style="text-align: left;">Asset Name</th>
                <th style="text-align: left;">Asset ID</th>
            </tr>`;

    assets.forEach(asset => {
        htmlContent += `<tr>
            <td style="font-weight: bold;">${asset.name}</td>
            <td style="font-family: monospace; font-size: 16px;">${asset.id}</td>
        </tr>`;
    });

    htmlContent += `</table></body></html>`;

    // 5. Open directly in a new tab (No Download)
    const blob = new Blob([htmlContent], { type: 'text/html' });
    const url = URL.createObjectURL(blob);
    window.open(url, '_blank');

    // Remove the dark overlay after it finishes
    setTimeout(() => { document.body.removeChild(overlay); }, 1000);
}