const BACKEND_HOST = process.env.BACKEND_HOST || '127.0.0.1';
const BACKEND_PORT = process.env.BACKEND_PORT || '8000';

/** @type {import('next').NextConfig} */
const nextConfig = {
  async rewrites() {
    return [
      {
        source: '/api/:path*',
        destination: `http://${BACKEND_HOST}:${BACKEND_PORT}/api/:path*`,
      },
    ];
  },
};
module.exports = nextConfig;