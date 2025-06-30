// .puppeteerrc.cjs
const { join } = require('path');

/**
 * @type {import("puppeteer").Configuration}
 */
module.exports = {
  // 跳过下载Chromium，使用系统安装的版本
  skipDownload: true,
  
  // 设置缓存目录
  cacheDirectory: join(__dirname, 'node_modules', '.cache', 'puppeteer'),
  
  // 设置可执行路径
  executablePath: process.env.PUPPETEER_EXECUTABLE_PATH || '/usr/bin/chromium',
};
