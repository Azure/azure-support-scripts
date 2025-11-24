/**
 * Manual Accessibility Check using axe-core
 * 
 * To run this:
 * 1. Install axe: npm install --save-dev @axe-core/playwright
 * 2. Run: node accessibility-check.js
 */

const { chromium } = require('@playwright/test');
const AxeBuilder = require('@axe-core/playwright').default;

async function runAccessibilityTest() {
  console.log('Starting accessibility scan...\n');
  
  const browser = await chromium.launch({ 
    headless: true,
    channel: 'msedge'  // Use Edge browser
  });
  const context = await browser.newContext();
  const page = await context.newPage();

  try {
    // Navigate to your app
    await page.goto('http://localhost:8080');
    
    console.log('Page loaded. Running axe-core scan...\n');

    // Run axe accessibility scan
    const accessibilityScanResults = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'])
      .analyze();

    console.log('='.repeat(60));
    console.log('ACCESSIBILITY SCAN RESULTS');
    console.log('='.repeat(60));
    console.log(`URL: ${accessibilityScanResults.url}`);
    console.log(`Violations found: ${accessibilityScanResults.violations.length}`);
    console.log(`Passes: ${accessibilityScanResults.passes.length}`);
    console.log(`Incomplete: ${accessibilityScanResults.incomplete.length}`);
    console.log('='.repeat(60));

    if (accessibilityScanResults.violations.length > 0) {
      console.log('\n🔴 VIOLATIONS FOUND:\n');
      
      accessibilityScanResults.violations.forEach((violation, index) => {
        console.log(`\n${index + 1}. ${violation.id}`);
        console.log(`   Impact: ${violation.impact?.toUpperCase() || 'N/A'}`);
        console.log(`   Description: ${violation.description}`);
        console.log(`   Help: ${violation.help}`);
        console.log(`   Help URL: ${violation.helpUrl}`);
        console.log(`   Affected elements: ${violation.nodes.length}`);
        
        violation.nodes.forEach((node, nodeIndex) => {
          console.log(`\n   Element ${nodeIndex + 1}:`);
          console.log(`     HTML: ${node.html.substring(0, 100)}${node.html.length > 100 ? '...' : ''}`);
          console.log(`     Target: ${node.target.join(' ')}`);
          
          if (node.failureSummary) {
            console.log(`     Issue: ${node.failureSummary}`);
          }
        });
        
        console.log('\n   ' + '-'.repeat(56));
      });
    } else {
      console.log('\n✅ No accessibility violations found!');
    }

    // Incomplete tests (need manual review)
    if (accessibilityScanResults.incomplete.length > 0) {
      console.log('\n\n⚠️  INCOMPLETE TESTS (Manual Review Needed):\n');
      
      accessibilityScanResults.incomplete.forEach((incomplete, index) => {
        console.log(`\n${index + 1}. ${incomplete.id}`);
        console.log(`   Description: ${incomplete.description}`);
        console.log(`   Help URL: ${incomplete.helpUrl}`);
        console.log(`   Affected elements: ${incomplete.nodes.length}`);
      });
    }

    console.log('\n' + '='.repeat(60));
    console.log('Scan complete!');
    console.log('='.repeat(60) + '\n');

  } catch (error) {
    console.error('Error during accessibility scan:', error);
  } finally {
    await browser.close();
  }
}

// Check if server is running
console.log('⚠️  Make sure your dev server is running on http://localhost:8080');
console.log('   You can start it with: npx http-server rca-tool/ -p 8080\n');

runAccessibilityTest();
