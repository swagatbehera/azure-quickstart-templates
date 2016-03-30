#!/usr/bin/python
import logging
import requests
import time

LOG = logging.getLogger(__name__)

class HiveSampleInstaller(object):
  @staticmethod
  def deploy_hive_samples():
    LOG.info("Deploying Hive samples")
    session = HiveSampleInstaller.get_session()
    LOG.debug("Got session for URL: %s", session.base_url)

    timeout_secs = (60 * 2)
    timeout_time = time.time() + timeout_secs
    login_success = False
    while time.time() < timeout_time:
      try:
        LOG.debug("Logging into Hue as admin")
        session.login('admin', 'admin')
        login_success = True
        break
      except Exception, e:
        LOG.debug("Failed to login to Hue, retrying in 10 seconds...")
        time.sleep(10)  # wait before next attempt

    if not login_success:
      LOG.info("Hue login exceeded timeout of %d seconds.", timeout_secs)
      raise Exception("Hue login exceeded timeout of %d seconds." % timeout_secs)

    # Logging in for the first time creates credentials and sets things up.
    # Give it some time. From looking at beeswax logs, it can take about 20 seconds.
    # Without this beeswax sample setup command fails most of the time by timing out
    wait_secs = 60
    LOG.debug("Sleeping for %d seconds...", wait_secs)
    time.sleep(wait_secs)

    LOG.debug("Installing beeswax examples")
    response = session.post('/beeswax/install_examples')
    LOG.debug("Got response: %s", response.text)

    response.raise_for_status()

  @staticmethod
  def get_session():
    """Get a Hue session to the first server in the list."""
    return HiveSampleInstaller.get_session_for_url(HiveSampleInstaller.get_server_urls()[0])

  @staticmethod
  def get_session_for_url(url):
    """Get a Hue session."""

    # wait for the server to be up, in case it was just started
    # Because we use self-signed certificates, the
    # requests library will fail with a secure cluster.
    # I'm not clear quite how to give requests the right key,
    # so, for the time being, we simplify ignore
    # verification.  See OPSAPS-28497
    HiveSampleInstaller.wait_for_url(url, timeout_seconds=300, verify=False)

    return Session(url)

  @staticmethod
  def wait_for_url(url, timeout_seconds=120, expected_response_code=None, verify=True):
    '''
    Wait for the http server is up or if optional expected_response_code is passed in
    wait for the expected response from the http server, until the user defined timeout is reached.
    '''

    deadline = time.time() + timeout_seconds
    while deadline > time.time():
      try:
        response = requests.get(url, verify=verify)
      except requests.exceptions.ConnectionError, e:
        LOG.debug("Error connecting to %s: %s" % (url, e))
      except Exception as e:
        LOG.exception("Error connecting to %s: %s" % (url, e))
      else:
        if expected_response_code is None or response.status_code == expected_response_code:
          return

    time.sleep(1)

    # If it gets past the loop without returning, you've timed out.
    raise Exception("Timed out waiting for %s." % (url,))

  ## some methods that I copied & pasted
  @staticmethod
  def get_server_urls():
    scheme = 'http'

    return ['%s://%s:%s' % (scheme, hostname, port)
        for hostname, port in HUE.get_hue_server_hosts_and_ports()]

class Session(object):
  def __init__(self, base_url):
    self.base_url = base_url
    self.session = requests.Session()

  def login(self, username, password):
    url = '/accounts/login/'

    response = self.get(url)
    response.raise_for_status()

    # Roughly as of Hue in CDH5.5, the referer needs to
    # be set.
    self.session.headers.update(dict(referer=response.url))

    response = self.post(url, data={'username': username, 'password': password})
    response.raise_for_status()

    # Hue doesn't return a 404 for a bad username/password combination
    assert "Invalid username or password" not in response.text, "Login failed"

  def install_hive_examples(self):
    response = self.post('/beeswax/install_examples')
    response.raise_for_status()

  def get(self, *args, **kwargs):
    return self._request(self.session.get, *args, **kwargs)

  def post(self, *args, **kwargs):
    return self._request(self.session.post, *args, **kwargs)

  def put(self, *args, **kwargs):
    return self._request(self.session.put, *args, **kwargs)

  def delete(self, *args, **kwargs):
    return self._request(self.session.delete, *args, **kwargs)

  def _request(self, method, url, *args, **kwargs):
    url = self.base_url + url

    try:
      csrf = self.session.cookies['csrftoken']
    except KeyError:
      pass
    else:
      headers = kwargs.get('headers', {})
      headers['X-CSRFToken'] = csrf
      kwargs['headers'] = headers

    # Because we use self-signed certificates, the
    # requests library will fail.  I'm not clear
    # quite how to give requests the right key,
    # so, for the time being, we simplify ignore
    # verification.  See OPSAPS-28497
    return method(url, *args, verify=False, **kwargs)


class HUE(object):

  @staticmethod
  def get_server_urls():
    '''
    NECESSARY
    :return:
    '''
    scheme = 'http'

    return ['%s://%s:%s' % (scheme, hostname, port)
        for hostname, port in HUE.get_hue_server_hosts_and_ports()]

  @staticmethod
  def get_hue_server_hosts_and_ports():
    hosts_and_ports = []

    hosts_and_ports.append(("dnspfx2a-mn0.azure.cloudera.com", 8888))
    return hosts_and_ports

  def get_session_for_url(self, url):
    """Get a Hue session."""

    # wait for the server to be up, in case it was just started
    # Because we use self-signed certificates, the
    # requests library will fail with a secure cluster.
    # I'm not clear quite how to give requests the right key,
    # so, for the time being, we simplify ignore
    # verification.  See OPSAPS-28497
    HiveSampleInstaller.wait_for_url(url, timeout_seconds=300, verify=False)

    return Session(url)

  def get_session(self):
    """Get a Hue session to the first server in the list."""
    return self.get_session_for_url(self.get_server_urls()[0])

  def deploy_hive_samples(self):
    LOG.info("Deploying Hive samples")
    session = self.get_session()
    LOG.debug("Got session for URL: %s", session.base_url)

    timeout_secs = (60 * 2)
    timeout_time = time.time() + timeout_secs
    login_success = False
    while time.time() < timeout_time:
      try:
        LOG.debug("Logging into Hue as admin")
        session.login('admin', 'admin')
        login_success = True
        break
      except Exception, e:
        LOG.debug("Failed to login to Hue, retrying in 10 seconds...")
        time.sleep(10)  # wait before next attempt

    if not login_success:
      LOG.info("Hue login exceeded timeout of %d seconds.", timeout_secs)
      raise Exception("Hue login exceeded timeout of %d seconds." % timeout_secs)

    # Logging in for the first time creates credentials and sets things up.
    # Give it some time. From looking at beeswax logs, it can take about 20 seconds.
    # Without this beeswax sample setup command fails most of the time by timing out
    wait_secs = 60
    LOG.debug("Sleeping for %d seconds...", wait_secs)
    time.sleep(wait_secs)

    LOG.debug("Installing beeswax examples")
    response = session.post('/beeswax/install_examples')
    LOG.debug("Got response: %s", response.text)

    response.raise_for_status()

if __name__ == '__main__':
  HiveSampleInstaller.deploy_hive_samples()


