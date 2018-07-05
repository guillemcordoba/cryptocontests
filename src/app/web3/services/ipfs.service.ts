import { Injectable } from '@angular/core';
import * as IPFS from 'ipfs-api';

export interface FileReceipt {
  path: string;
  hash: string;
  size: number;
}

type IpfsContent = Buffer | ReadableStream;

export interface IpfsFile {
  path: string;
  content: IpfsContent;
}

@Injectable({
  providedIn: 'root'
})
export class IpfsService {

  host = 'ipfs.infura.io';
  ipfs: IPFS;

  constructor() {
    this.ipfs = new IPFS({ host: this.host, port: 5001, protocol: 'https' });
  }

  public add(data: IpfsContent | IpfsFile[], options: any = {}): Promise<FileReceipt> {
    return this.ipfs.files.add(data, options);
  }

  public get(ipfsPath: string): Promise<IpfsFile> {
    return this.ipfs.files.get(ipfsPath);
  }
}