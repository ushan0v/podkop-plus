import { Podkop } from '../../types';
import { PODKOP_UCI_PACKAGE } from '../../../constants';

export async function getConfigSections(): Promise<Podkop.ConfigSection[]> {
  return uci
    .load(PODKOP_UCI_PACKAGE)
    .then(() => uci.sections(PODKOP_UCI_PACKAGE));
}
