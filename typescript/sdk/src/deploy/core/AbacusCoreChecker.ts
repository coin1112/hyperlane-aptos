import { utils } from '@abacus-network/utils';

import { AbacusCore } from '../../core/AbacusCore';
import { ChainNameToDomainId } from '../../domains';
import { ChainName } from '../../types';
import { AbacusAppChecker } from '../AbacusAppChecker';

import {
  CoreConfig,
  CoreViolationType,
  MailboxViolation,
  MailboxViolationType,
} from './types';

export class AbacusCoreChecker<
  Chain extends ChainName,
> extends AbacusAppChecker<Chain, AbacusCore<Chain>, CoreConfig> {
  async checkChain(chain: Chain): Promise<void> {
    const config = this.configMap[chain];
    // skip chains that are configured to be removed
    if (config.remove) {
      return;
    }

    await this.checkDomainOwnership(chain);
    await this.checkProxiedContracts(chain);
    await this.checkMailbox(chain);
    // await this.checkDefaultZone(chain);
    await this.checkInterchainGasPaymaster(chain);
  }

  async checkDomainOwnership(chain: Chain): Promise<void> {
    const config = this.configMap[chain];
    if (config.owner) {
      const contracts = this.app.getContracts(chain);
      const ownables = [
        contracts.upgradeBeaconController,
        // contracts.mailbox.contract,
        contracts.defaultZone,
      ];
      return this.checkOwnership(chain, config.owner, ownables);
    }
  }

  async checkMailbox(chain: Chain): Promise<void> {
    const contracts = this.app.getContracts(chain);
    const mailbox = contracts.mailbox.contract;
    const localDomain = await mailbox.localDomain();
    utils.assert(localDomain === ChainNameToDomainId[chain]);

    const actualZone = await mailbox.defaultZone();
    const expectedZone = contracts.defaultZone.address;
    if (actualZone !== expectedZone) {
      const violation: MailboxViolation = {
        type: CoreViolationType.Mailbox,
        mailboxType: MailboxViolationType.DefaultZone,
        contract: mailbox,
        chain,
        actual: actualZone,
        expected: expectedZone,
      };
      this.addViolation(violation);
    }
  }

  async checkProxiedContracts(chain: Chain): Promise<void> {
    const contracts = this.app.getContracts(chain);
    await this.checkUpgradeBeacon(
      chain,
      'Mailbox',
      contracts.mailbox.addresses,
    );
  }

  async checkInterchainGasPaymaster(chain: Chain): Promise<void> {
    const contracts = this.app.getContracts(chain);
    await this.checkUpgradeBeacon(
      chain,
      'InterchainGasPaymaster',
      contracts.interchainGasPaymaster.addresses,
    );
  }
}
