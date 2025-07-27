// Bridgelink Preprocessor Script - Base64 Decoding
// This script preprocesses incoming messages by decoding base64 content

// Modify the message variable below to pre process data
//return message;

try {
  var base64string = message.toString();
  var rawBytes = FileUtil.decode(base64string);
  var decoded = new java.lang.String(rawBytes, 'UTF-8');
  message = decoded; // overwrite inbound
  return message;
  //logger.info('Decoded message length: ' + decoded.length);
} catch (e) {
  logger.error('Base64 decode error: ' + e);
}
