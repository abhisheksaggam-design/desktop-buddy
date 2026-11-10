import Link from "next/link";
import Image from "next/image";
import { site } from "../../lib/site";

export function Footer() {
  return (
    <footer className="footer">
      <div className="wrap footer__inner">
        <div className="footer__about">
          <Image src="/shots/app-icon.png" alt="" width={32} height={32} />
          <p>
            {site.name} {site.version} for {site.minOS}.
            <br />
            Made by <a href={site.publisherUrl}>{site.publisher}</a>.
          </p>
        </div>
        <ul className="footer__links">
          <li><Link href="/get-started/">Get started</Link></li>
          <li><Link href="/privacy/">App privacy</Link></li>
          <li><a href={site.companyPrivacyUrl}>Dynamatix privacy policy</a></li>
          <li><a href={site.termsUrl}>Terms</a></li>
          <li><a href={`mailto:${site.contactEmail}`}>{site.contactEmail}</a></li>
        </ul>
      </div>
    </footer>
  );
}
