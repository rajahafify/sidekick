/// The image type of some bytes, read from their first bytes. Null for anything but a JPEG, PNG or WebP.
String? imageType(List<int> bytes) {
  bool at(int start, List<int> signature) {
    if (bytes.length < start + signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[start + i] != signature[i]) return false;
    }
    return true;
  }

  if (at(0, [0xff, 0xd8, 0xff])) return 'image/jpeg';
  if (at(0, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return 'image/png';
  // WebP is "RIFF", four bytes of size, then "WEBP".
  if (at(0, [0x52, 0x49, 0x46, 0x46]) && at(8, [0x57, 0x45, 0x42, 0x50])) return 'image/webp';
  return null;
}
