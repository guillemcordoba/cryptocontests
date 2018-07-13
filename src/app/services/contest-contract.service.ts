import { environment } from './../../environments/environment';
import { TransactionReceipt, PromiEvent, Contract } from 'web3/types';
import { SmartContractService } from './../web3/services/smart-contract.service';
import { Injectable } from '@angular/core';
import {
  Observable,
  range,
  from,
  of as observableOf,
  forkJoin,
  combineLatest
} from 'rxjs';
import {
  switchMap,
  mergeAll,
  map,
  concatMap,
  flatMap,
  tap,
  mergeMap,
  defaultIfEmpty
} from 'rxjs/operators';
import { Contest, Participation, ContestPhase } from '../state/contest.model';
import * as _ from 'lodash';
import { Web3Service } from '../web3/services/web3.service';
import { TransactionStateService } from '../web3/services/transaction-state.service';
import { CryptoCurrency } from '../web3/transaction.model';
import { CurrencyService } from '../web3/services/currency.service';
import {
  IpfsService,
  FileReceipt,
  IpfsFile
} from '../web3/services/ipfs.service';

declare function require(url: string);
const ContestController = require('./../../../build/contracts/ContestController.json');

@Injectable({
  providedIn: 'root'
})
export class ContestContractService {
  protected contract: Contract;

  constructor(
    private web3Service: Web3Service,
    private transactionStates: TransactionStateService,
    private currencyService: CurrencyService,
    private ipfs: IpfsService
  ) {
    this.contract = this.web3Service.newContract(
      ContestController.abi,
      environment.contractAddress
    );
  }

  /**
   * All this methods composed help return a contest
   */

  getDefaultAccount = from(this.web3Service.getDefaultAccount());
  getAllTags = (address: string) =>
    this.contract.methods.getAllTags().call({
      from: address
    });
  getTotalContestCount = (address: string) =>
    this.contract.methods.getTotalContestsCount().call({
      from: address
    });
  getContestHashByIndex = (address: string, index: number) =>
    this.contract.methods.contestHashes(index).call({
      from: address
    });
  getContestByHash = (address: string, contestHash: string) =>
    this.contract.methods.getContest(contestHash).call({
      from: address
    });
  getParticipationsByContestHash = (address: string, contestHash: string) =>
    this.contract.methods.getParticipationsByContest(contestHash).call({
      from: address
    });
  getParticipation = (
    address: string,
    contestHash: string,
    participationHash: string
  ) =>
    this.contract.methods
      .getParticipation(contestHash, participationHash)
      .call({
        from: address
      });
  responseToContest = (response: any) =>
    <Contest>{
      id: response.contestHash,
      title: response.title,
      initialDate: response.startContest * 1000,
      participationLimitDate: response.timeToCandidatures * 1000,
      endDate: response.endContest * 1000,
      prize: {
        value: response.award,
        currency: CryptoCurrency.WEIS
      },
      tags: response.tags.map(tag => this.web3Service.bytesToString(tag))
    };
  responseToParticipation = (response: any, ipfsFile: IpfsFile) =>
    <Participation>{
      title: response.title,
      creator: response.owner,
      date: response.creationDate,
      content: {
        hash: response.content,
        content: ipfsFile.content
      },
      votes: response.votes
    };

  /**
   * Gets all the tags
   */
  public getTags(): Observable<string[]> {
    return this.getDefaultAccount.pipe(
      switchMap((address: string) => this.getAllTags(address)),
      map((tags: any[]) => tags.map(tag => this.web3Service.bytesToString(tag)))
    );
  }

  /**
   * Get a contest from the contest hash
   */
  public getContest(
    contestHash: string,
    address?: string
  ): Observable<Contest> {
    return (address ? observableOf(address) : this.getDefaultAccount).pipe(
      switchMap(add => this.getContestByHash(add, contestHash)),
      map((response: any) => this.responseToContest(response))
    );
  }

  /**
   * Gets all the contests
   */
  public getContests(filter: Partial<Contest>): Observable<Contest[]> {
    let address: string;
    return this.getDefaultAccount.pipe(
      tap(add => (address = add)),
      switchMap(() => this.getTotalContestCount(address)),
      switchMap((contestCount: number) =>
        forkJoin(
          _
            .range(0, contestCount)
            .map((index: number) =>
              from(this.getContestHashByIndex(address, index)).pipe(
                switchMap((contestHash: string) =>
                  this.getContest(contestHash, address)
                )
              )
            )
        )
      ),
      defaultIfEmpty([])
    );
  }

  /**
   * Creates a contest
   */
  public createContest(contest: Contest): Observable<TransactionReceipt> {
    // TODO: uncomment when the contest includes an image
    // const pinFile: Observable<FileReceipt> = from(this.ipfs.addFile(<Buffer>contest.imageHash));
    const ipfsFiles: IpfsFile[] = [
      {
        path: 'image.png',
        content: contest.additionalContent.content.image
      },
      {
        path: 'description.txt',
        content: new Buffer(contest.additionalContent.content.description)
      }
    ];
    const additionalContestContent = from(
      this.ipfs.add(ipfsFiles, {
        pin: false,
        wrapWithDirectory: true
      })
    );

    return this.getDefaultAccount.pipe(
      //      withLatestFrom(additionalContestContent),
      //      map(([address, receipt]) =>
      map(address =>
        this.contract.methods
          .setNewContest(
            contest.title,
            contest.tags.map(tag => this.web3Service.stringToBytes(tag)),
            contest.initialDate / 1000,
            contest.endDate / 1000,
            contest.participationLimitDate / 1000,
            0,
            '0x341f85f5eca6304166fcfb6f591d49f6019f23fa39be0615e6417da06bf747ce'
          )
          .send({
            from: address,
            value: this.currencyService.ethToWeis(contest.prize.value),
            gas: 4712388,
            gasPrice: 20
          })
      ),
      tap(txPromise =>
        this.transactionStates.registerTransaction(txPromise, contest.title)
      ),
      switchMap(promise => promise)
    );
  }

  /**
   * Gets all the participations for the given contest
   */
  public getContestParticipations(
    contestHash: string
  ): Observable<Participation[]> {
    let address: string;

    return this.getDefaultAccount.pipe(
      tap(add => (address = add)),
      switchMap(() =>
        this.getParticipationsByContestHash(address, contestHash)
      ),
      switchMap(hashes =>
        forkJoin(
          hashes.map((participationHash: string) =>
            combineLatest(
              this.getParticipation(address, contestHash, participationHash),
              this.ipfs.get(this.ipfs.getIpfsHashFromBytes32(participationHash))
            ).pipe(
              map(([response, ipfsFile]) =>
                this.responseToParticipation(response, ipfsFile[0])
              )
            )
          )
        )
      ),
      defaultIfEmpty([])
    );
  }

  /**
   * Creates a participation
   */
  public createParticipation(
    contestHash: string,
    participation: Participation
  ): Observable<TransactionReceipt> {
    // Store participation content on ipfs and retrieve hash
    const participationContent = from(
      this.ipfs.add(participation.content.content, {
        pin: false
      })
    );

    return combineLatest(this.getDefaultAccount, participationContent).pipe(
      map(([address, receipt]) =>
        this.contract.methods
          .setNewParticipation(
            contestHash,
            participation.title,
            this.ipfs.getBytes32FromIpfsHash(receipt[0].hash)
          )
          .send({
            from: address,
            gas: 4712388,
            gasPrice: 20
          })
      ),
      tap(txPromise =>
        this.transactionStates.registerTransaction(
          txPromise,
          participation.title
        )
      ),
      switchMap(promise => promise)
    );
  }
}
