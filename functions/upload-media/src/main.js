const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');

module.exports = async ({ req, res, log, error }) => {
  try {
    // Parse multipart form data
    const contentType = req.headers['content-type'] || '';
    if (!contentType.includes('multipart/form-data')) {
      return res.json({ error: 'Content-Type must be multipart/form-data' }, 400);
    }

    // Get file from request body
    const file = req.body;
    const fileName = req.headers['x-file-name'] || `${Date.now()}_upload`;
    const fileType = req.headers['x-file-type'] || 'application/octet-stream';

    // Initialize S3 client for Wasabi
    const s3Client = new S3Client({
      region: process.env.WASABI_REGION || 'us-east-1',
      endpoint: process.env.WASABI_ENDPOINT || 'https://s3.wasabisys.com',
      credentials: {
        accessKeyId: process.env.WASABI_ACCESS_KEY,
        secretAccessKey: process.env.WASABI_SECRET_KEY
      }
    });

    // Upload to Wasabi
    const command = new PutObjectCommand({
      Bucket: process.env.WASABI_BUCKET || 'xapzap-media',
      Key: `media/${fileName}`,
      Body: file,
      ContentType: fileType
    });

    await s3Client.send(command);

    log(`File uploaded successfully: ${fileName}`);

    return res.json({
      success: true,
      url: `/media/${fileName}`,
      fileName
    });

  } catch (err) {
    error(`Upload failed: ${err.message}`);
    return res.json({ error: err.message }, 500);
  }
};
