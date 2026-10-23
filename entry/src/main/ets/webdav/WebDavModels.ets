export class WebDavConnection {
  id: string = '';
  name: string = '';
  baseUrl: string = '';
  username: string = '';
  libraryRoot: string = '';
  rememberPassword: boolean = true;
  secretStorageVersion: number = 1;
  enabled: boolean = true;
  createdAt: number = 0;
  updatedAt: number = 0;
}

export class WebDavEntry {
  name: string = '';
  relativePath: string = '';
  href: string = '';
  directory: boolean = false;
  size: number = 0;
  lastModified: number = 0;
  etag: string = '';
  contentType: string = '';

  readableBook(): boolean {
    if (this.directory) return false;
    const value = this.name.toLowerCase();
    return value.endsWith('.txt') || value.endsWith('.epub') || value.endsWith('.mobi');
  }

  format(): string {
    const value = this.name.toLowerCase();
    if (value.endsWith('.epub')) return 'epub';
    if (value.endsWith('.mobi')) return 'mobi';
    if (value.endsWith('.txt')) return 'txt';
    return '';
  }
}

export class WebDavConnectionTestResult {
  ok: boolean = false;
  statusCode: number = 0;
  message: string = '';
}

export class WebDavFileInfo {
  exists: boolean = false;
  statusCode: number = 0;
  size: number = 0;
  lastModified: number = 0;
  etag: string = '';
  contentType: string = '';
}

export class WebDavDownloadResult {
  path: string = '';
  size: number = 0;
  etag: string = '';
  lastModified: number = 0;
}
