import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
export function database(){if(!getApps().length)initializeApp();return getFirestore();}
